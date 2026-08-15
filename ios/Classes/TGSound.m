#import "TGSound.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

static const NSUInteger kMaxEffectPlayers = 4;

@implementation TGSound {
	NSData *_effectData;                        // effect mode: shared sample buffer
	NSMutableArray<AVAudioPlayer *> *_players;  // effect: pool; music: one player
	BOOL _resumeOnBecomeActive;
	float _volume; // both accessors are hand-written, so synthesize manually
}

@synthesize volume = _volume;

- (instancetype)initWithURL:(NSURL *)url music:(BOOL)music
{
	if (self = [super init]) {
		_music = music;
		_volume = 1.0f;
		_players = [NSMutableArray array];

		// Game audio: don't interrupt background music apps, respect the
		// silent switch — set once for the whole app
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:nil];
		});

		if (music) {
			AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:nil];
			if (player != nil) {
				[player prepareToPlay];
				[_players addObject:player];
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
			_effectData = [NSData dataWithContentsOfURL:url];
			if (_effectData == nil) {
				NSLog(@"[ERROR] Could not load sound: %@", url);
			} else {
				AVAudioPlayer *player = [self makeEffectPlayer];
				[player prepareToPlay]; // pre-decode so the first play is instant
			}
		}
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (AVAudioPlayer *)makeEffectPlayer
{
	AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithData:_effectData error:nil];
	if (player != nil) {
		[_players addObject:player];
	}
	return player;
}

- (void)play
{
	if (_music) {
		AVAudioPlayer *player = _players.firstObject;
		player.volume = self.volume;
		player.numberOfLoops = self.loop ? -1 : 0;
		[player play];
		return;
	}
	// Effect: grab an idle player from the pool so plays overlap; if all
	// are busy and the pool is full, restart the first one
	AVAudioPlayer *player = nil;
	for (AVAudioPlayer *candidate in _players) {
		if (!candidate.playing) {
			player = candidate;
			break;
		}
	}
	if (player == nil) {
		player = (_players.count < kMaxEffectPlayers) ? [self makeEffectPlayer] : _players.firstObject;
	}
	if (player == nil) {
		return;
	}
	player.volume = self.volume;
	player.numberOfLoops = self.loop ? -1 : 0;
	player.currentTime = 0;
	[player play];
}

- (void)pause
{
	_resumeOnBecomeActive = NO; // an explicit pause survives the lifecycle
	for (AVAudioPlayer *player in _players) {
		if (player.playing) {
			[player pause];
		}
	}
}

- (void)stop
{
	// An explicit stop() must win over a pending lifecycle auto-resume
	_resumeOnBecomeActive = NO;
	for (AVAudioPlayer *player in _players) {
		if (player.playing) {
			[player pause];
		}
		player.currentTime = 0;
	}
}

- (void)setVolume:(float)volume
{
	@synchronized (self) {
		_volume = volume;
	}
	for (AVAudioPlayer *player in _players) {
		player.volume = volume;
	}
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
	AVAudioPlayer *player = _players.firstObject;
	if (player.playing) {
		[player pause];
		_resumeOnBecomeActive = YES;
	}
}

- (void)appDidBecomeActive
{
	if (_resumeOnBecomeActive) {
		_resumeOnBecomeActive = NO;
		[_players.firstObject play];
	}
}

@end
