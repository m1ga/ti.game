#import "TiGameSoundProxy.h"
#import "TGValues.h"

@implementation TiGameSoundProxy {
	TGSound *_sound;
}

- (NSString *)apiName
{
	return @"ti.game.Sound";
}

- (void)_initWithProperties:(NSDictionary *)properties
{
	NSString *url = [TiUtils stringValue:properties[@"url"]];
	if (url == nil) {
		NSLog(@"[ERROR] createSound requires a 'url' property");
	} else {
		// Like Android, a module proxy may resolve relative to the module's
		// asset space — fall back to the app's Resources directory if the
		// resolved file doesn't exist
		NSURL *resolved = [TiUtils toURL:url proxy:self];
		if (resolved.isFileURL
				&& ![[NSFileManager defaultManager] fileExistsAtPath:resolved.path]) {
			resolved = [NSURL fileURLWithPath:
				[[TiHost resourcePath] stringByAppendingPathComponent:url]];
		}
		_sound = [[TGSound alloc] initWithURL:resolved
										music:[TiUtils boolValue:properties[@"music"] def:NO]];
		_sound.volume = [TiUtils floatValue:properties[@"volume"] def:1];
		_sound.loop = [TiUtils boolValue:properties[@"loop"] def:NO];
	}
	[super _initWithProperties:properties];
}

#pragma mark Playback

- (void)play:(id)unused
{
	[_sound play];
}

- (void)pause:(id)unused
{
	[_sound pause];
}

- (void)stop:(id)unused
{
	[_sound stop];
}

#pragma mark Properties

- (void)setVolume:(id)value
{
	_sound.volume = [TGValues ratio:value fallback:1];
}

- (NSNumber *)volume
{
	return @(_sound.volume);
}

- (void)setLoop:(id)value
{
	_sound.loop = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)loop
{
	return @(_sound.loop);
}

- (NSNumber *)music
{
	return @(_sound.music);
}

@end
