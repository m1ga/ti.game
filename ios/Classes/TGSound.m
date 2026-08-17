#import "TGSound.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

static const NSUInteger kMaxEffectPlayers = 4;

@interface TGEffectVoice : NSObject
@property (nonatomic, strong) AVAudioPlayerNode *node;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL looping;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, copy) NSString *ownerToken;
@end

@implementation TGEffectVoice
@end

/** One engine and one serial control queue for every short game effect. */
@interface TGEffectEngine : NSObject
@property (nonatomic, readonly) AVAudioEngine *engine;
@property (nonatomic, readonly) dispatch_queue_t queue;
+ (instancetype)shared;
- (BOOL)ensureRunning;
- (AVAudioPCMBuffer *)bufferForURL:(NSURL *)url;
- (NSString *)registerFormat:(AVAudioFormat *)format;
- (void)playBuffer:(AVAudioPCMBuffer *)buffer
		  formatKey:(NSString *)formatKey
		 ownerToken:(NSString *)ownerToken
			 volume:(float)volume
			   loop:(BOOL)loop;
- (void)pauseOwner:(NSString *)ownerToken formatKey:(NSString *)formatKey;
- (void)stopOwner:(NSString *)ownerToken formatKey:(NSString *)formatKey;
- (void)setVolume:(float)volume ownerToken:(NSString *)ownerToken formatKey:(NSString *)formatKey;
@end

@implementation TGEffectEngine {
	BOOL _interrupted;
	NSMutableDictionary<NSString *, NSArray<TGEffectVoice *> *> *_formatVoices;
	NSMutableDictionary<NSString *, AVAudioPCMBuffer *> *_bufferCache;
}

+ (instancetype)shared
{
	static TGEffectEngine *engine;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		engine = [[TGEffectEngine alloc] init];
	});
	return engine;
}

- (instancetype)init
{
	if (self = [super init]) {
		_queue = dispatch_queue_create("ti.game.audio", DISPATCH_QUEUE_SERIAL);
		dispatch_set_target_queue(_queue,
			dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0));
		_engine = [[AVAudioEngine alloc] init];
		_formatVoices = [NSMutableDictionary dictionary];
		_bufferCache = [NSMutableDictionary dictionary];
		AVAudioSession *session = [AVAudioSession sharedInstance];
		[session setCategory:AVAudioSessionCategoryAmbient error:nil];

		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center addObserver:self selector:@selector(appWillResignActive)
					   name:UIApplicationWillResignActiveNotification object:nil];
		[center addObserver:self selector:@selector(appDidBecomeActive)
					   name:UIApplicationDidBecomeActiveNotification object:nil];
	}
	return self;
}

- (NSString *)keyForFormat:(AVAudioFormat *)format
{
	AudioStreamBasicDescription description = *format.streamDescription;
	return [NSString stringWithFormat:@"%u:%.6f:%u:%u:%u",
		(unsigned int)description.mFormatID,
		description.mSampleRate,
		(unsigned int)description.mChannelsPerFrame,
		(unsigned int)description.mBitsPerChannel,
		(unsigned int)description.mFormatFlags];
}

- (AVAudioPCMBuffer *)bufferForURL:(NSURL *)url
{
	__block AVAudioPCMBuffer *buffer;
	dispatch_sync(_queue, ^{
		NSString *cacheKey = url.path ?: url.absoluteString;
		buffer = self->_bufferCache[cacheKey];
		if (buffer != nil) {
			return;
		}

		NSError *error = nil;
		AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
		AVAudioFramePosition length = file.length;
		if (file == nil || length <= 0 || length > UINT32_MAX) {
			NSLog(@"[ERROR] Could not load sound %@: %@", url, error);
			return;
		}
		buffer = [[AVAudioPCMBuffer alloc]
			initWithPCMFormat:file.processingFormat
			frameCapacity:(AVAudioFrameCount)length];
		if (![file readIntoBuffer:buffer error:&error]) {
			NSLog(@"[ERROR] Could not decode sound %@: %@", url, error);
			buffer = nil;
			return;
		}
		self->_bufferCache[cacheKey] = buffer;
	});
	return buffer;
}

- (NSString *)registerFormat:(AVAudioFormat *)format
{
	NSString *formatKey = [self keyForFormat:format];
	dispatch_sync(_queue, ^{
		if (self->_formatVoices[formatKey] != nil) {
			return;
		}
		NSMutableArray<TGEffectVoice *> *voices =
			[NSMutableArray arrayWithCapacity:kMaxEffectPlayers];
		for (NSUInteger index = 0; index < kMaxEffectPlayers; index++) {
			TGEffectVoice *voice = [[TGEffectVoice alloc] init];
			voice.node = [[AVAudioPlayerNode alloc] init];
			[self->_engine attachNode:voice.node];
			[self->_engine connect:voice.node
							to:self->_engine.mainMixerNode
						format:format];
			[voices addObject:voice];
		}
		self->_formatVoices[formatKey] = [voices copy];
		[self ensureRunning];
	});
	return formatKey;
}

- (void)playBuffer:(AVAudioPCMBuffer *)buffer
		  formatKey:(NSString *)formatKey
		 ownerToken:(NSString *)ownerToken
			 volume:(float)volume
			   loop:(BOOL)loop
{
	dispatch_async(_queue, ^{
		NSArray<TGEffectVoice *> *voices = self->_formatVoices[formatKey];
		TGEffectVoice *voice = nil;
		for (TGEffectVoice *candidate in voices) {
			if (!candidate.busy) {
				voice = candidate;
				break;
			}
		}
		if (voice == nil) {
			for (TGEffectVoice *candidate in voices) {
				if (!candidate.looping) {
					voice = candidate;
					break;
				}
			}
			voice = voice ?: voices.firstObject;
			[voice.node stop];
		}
		if (voice == nil) {
			return;
		}
		voice.busy = YES;
		voice.looping = loop;
		voice.ownerToken = ownerToken;
		voice.generation++;
		NSUInteger generation = voice.generation;
		voice.node.volume = volume;
		AVAudioPlayerNodeBufferOptions options = loop
			? AVAudioPlayerNodeBufferLoops : 0;
		[voice.node scheduleBuffer:buffer
						 atTime:nil
						 options:options
			 completionHandler:loop ? nil : ^{
			dispatch_async(self->_queue, ^{
				if (voice.generation == generation) {
					voice.busy = NO;
					voice.looping = NO;
					voice.ownerToken = nil;
				}
			});
		}];
		[self ensureRunning];
		[voice.node play];
	});
}

- (void)pauseOwner:(NSString *)ownerToken formatKey:(NSString *)formatKey
{
	dispatch_async(_queue, ^{
		for (TGEffectVoice *voice in self->_formatVoices[formatKey]) {
			if ([voice.ownerToken isEqualToString:ownerToken]) {
				[voice.node pause];
			}
		}
	});
}

- (void)stopOwner:(NSString *)ownerToken formatKey:(NSString *)formatKey
{
	if (ownerToken == nil || formatKey == nil) {
		return;
	}
	dispatch_async(_queue, ^{
		for (TGEffectVoice *voice in self->_formatVoices[formatKey]) {
			if ([voice.ownerToken isEqualToString:ownerToken]) {
				voice.generation++;
				voice.busy = NO;
				voice.looping = NO;
				voice.ownerToken = nil;
				[voice.node stop];
			}
		}
	});
}

- (void)setVolume:(float)volume ownerToken:(NSString *)ownerToken formatKey:(NSString *)formatKey
{
	dispatch_async(_queue, ^{
		for (TGEffectVoice *voice in self->_formatVoices[formatKey]) {
			if ([voice.ownerToken isEqualToString:ownerToken]) {
				voice.node.volume = volume;
			}
		}
	});
}

- (BOOL)ensureRunning
{
	if (_engine.running) {
		return YES;
	}
	NSError *error = nil;
	BOOL success = [_engine startAndReturnError:&error];
	if (!success) {
		NSLog(@"[ERROR] Could not start shared game audio engine: %@", error);
	}
	return success;
}

- (void)appWillResignActive
{
	dispatch_async(_queue, ^{
		if (self->_engine.running) {
			[self->_engine pause];
			self->_interrupted = YES;
		}
	});
}

- (void)appDidBecomeActive
{
	dispatch_async(_queue, ^{
		if (self->_interrupted) {
			self->_interrupted = NO;
			[self ensureRunning];
		}
	});
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

@implementation TGSound {
	AVAudioPCMBuffer *_effectBuffer;
	NSString *_effectFormatKey;
	NSString *_effectToken;
	AVAudioPlayer *_musicPlayer;
	BOOL _resumeOnBecomeActive;
	float _volume; // both accessors are hand-written, so synthesize manually
}

@synthesize volume = _volume;

- (instancetype)initWithURL:(NSURL *)url music:(BOOL)music
{
	if (self = [super init]) {
		_music = music;
		_volume = 1.0f;

		// Game audio: don't interrupt background music apps, respect the
		// silent switch — set once for the whole app
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:nil];
		});

		if (music) {
			_musicPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:nil];
			if (_musicPlayer != nil) {
				[_musicPlayer prepareToPlay];
			} else {
				NSLog(@"[ERROR] Could not load sound: %@", url);
			}
			// Music follows the app lifecycle, like the render loop
			NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
			[center addObserver:self selector:@selector(appWillResignActive)
						   name:UIApplicationWillResignActiveNotification object:nil];
			[center addObserver:self selector:@selector(appDidBecomeActive)
						   name:UIApplicationDidBecomeActiveNotification object:nil];
		} else {
			TGEffectEngine *shared = [TGEffectEngine shared];
			_effectBuffer = [shared bufferForURL:url];
			if (_effectBuffer != nil) {
				_effectFormatKey = [shared registerFormat:_effectBuffer.format];
				_effectToken = [NSUUID UUID].UUIDString;
			}
		}
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if (!_music) {
		[[TGEffectEngine shared] stopOwner:_effectToken formatKey:_effectFormatKey];
	}
}

- (void)play
{
	if (_music) {
		if (_musicPlayer == nil) {
			return;
		}
		_musicPlayer.volume = self.volume;
		_musicPlayer.numberOfLoops = self.loop ? -1 : 0;
		[_musicPlayer play];
		return;
	}
	if (_effectBuffer == nil || _effectFormatKey == nil) {
		return;
	}

	// Scheduling is deliberately asynchronous: JavaScript never waits for
	// graph or device work, while the serial queue preserves play order.
	[[TGEffectEngine shared] playBuffer:_effectBuffer
							  formatKey:_effectFormatKey
							 ownerToken:_effectToken
								 volume:self.volume
								   loop:self.loop];
}

- (void)pause
{
	_resumeOnBecomeActive = NO; // an explicit pause survives the lifecycle
	if (_music) {
		[_musicPlayer pause];
		return;
	}
	[[TGEffectEngine shared] pauseOwner:_effectToken formatKey:_effectFormatKey];
}

- (void)stop
{
	// An explicit stop() must win over a pending lifecycle auto-resume
	_resumeOnBecomeActive = NO;
	if (_music) {
		[_musicPlayer stop];
		_musicPlayer.currentTime = 0;
		return;
	}
	[[TGEffectEngine shared] stopOwner:_effectToken formatKey:_effectFormatKey];
}

- (void)setVolume:(float)volume
{
	@synchronized (self) {
		_volume = volume;
	}
	if (_music) {
		_musicPlayer.volume = volume;
		return;
	}
	[[TGEffectEngine shared] setVolume:volume
						 ownerToken:_effectToken
						  formatKey:_effectFormatKey];
}

- (float)volume
{
	@synchronized (self) {
		return _volume;
	}
}

// --- App lifecycle (music mode only) ------------------------------------

- (void)appWillResignActive
{
	if (_musicPlayer.playing) {
		[_musicPlayer pause];
		_resumeOnBecomeActive = YES;
	}
}

- (void)appDidBecomeActive
{
	if (_resumeOnBecomeActive) {
		_resumeOnBecomeActive = NO;
		[_musicPlayer play];
	}
}

@end
