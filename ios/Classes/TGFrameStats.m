#import "TGFrameStats.h"
#import <math.h>
#import <stdlib.h>
#import <string.h>

static const NSUInteger kMaxSamples = 240;
static const CFTimeInterval kWindowSeconds = 1.0;

static int compareSamples(const void *left, const void *right)
{
	double a = *(const double *)left;
	double b = *(const double *)right;
	return (a > b) - (a < b);
}

@implementation TGFrameStats {
	double _samples[kMaxSamples];
	double _sortBuffer[kMaxSamples];
	NSUInteger _sampleCount;
	BOOL _windowOpen;
	CFTimeInterval _windowStart;
	double _totalCpuMs;
	double _maxCpuMs;
	double _totalUpdateMs;
	double _totalTexturePrepareMs;
	double _totalBatchMs;
	double _totalPresentMs;
	int _measuredFrames;
	int _droppedFrames;
	int _presentFailures;
}

- (void)reset
{
	_windowOpen = NO;
	_sampleCount = 0;
	_totalCpuMs = 0;
	_maxCpuMs = 0;
	_totalUpdateMs = 0;
	_totalTexturePrepareMs = 0;
	_totalBatchMs = 0;
	_totalPresentMs = 0;
	_measuredFrames = 0;
	_droppedFrames = 0;
	_presentFailures = 0;
}

- (void)addFrameCpuMs:(double)cpuMs
			presentMs:(double)presentMs
			presented:(BOOL)presented
				  now:(CFTimeInterval)now
			 interval:(CFTimeInterval)interval
			   target:(CFTimeInterval)target
{
	if (!_windowOpen) {
		[self reset];
		_windowOpen = YES;
		_windowStart = now;
	}
	if (_sampleCount < kMaxSamples) {
		_samples[_sampleCount++] = cpuMs;
	}
	_totalCpuMs += cpuMs;
	if (cpuMs > _maxCpuMs) {
		_maxCpuMs = cpuMs;
	}
	_totalUpdateMs += self.updateMs;
	_totalTexturePrepareMs += self.texturePrepareMs;
	_totalBatchMs += self.batchMs;
	_totalPresentMs += presentMs;
	_measuredFrames++;
	if (!presented) {
		_presentFailures++;
	}

	if (target > 0.0 && interval > target * 1.5) {
		long intervals = lround(interval / target);
		if (intervals > 1) {
			_droppedFrames += (int)(intervals - 1);
		}
	}
}

- (BOOL)windowClosed:(CFTimeInterval)now
{
	return _windowOpen && (now - _windowStart) >= kWindowSeconds;
}

- (TGFrameStatsSnapshot)closeWindow:(CFTimeInterval)now
{
	double elapsed = now - _windowStart;
	int frames = MAX(1, _measuredFrames);

	TGFrameStatsSnapshot snapshot;
	memset(&snapshot, 0, sizeof(snapshot));
	snapshot.fps = (elapsed > 0) ? _measuredFrames / elapsed : 0;
	snapshot.averageCpuMs = _totalCpuMs / frames;
	snapshot.maxCpuMs = _maxCpuMs;
	snapshot.p95CpuMs = [self percentile95];
	snapshot.averageUpdateMs = _totalUpdateMs / frames;
	snapshot.averageTexturePrepareMs = _totalTexturePrepareMs / frames;
	snapshot.averageBatchMs = _totalBatchMs / frames;
	snapshot.averagePresentMs = _totalPresentMs / frames;
	snapshot.droppedFrames = _droppedFrames;
	snapshot.presentFailures = _presentFailures;
	snapshot.sprites = self.sprites;
	snapshot.visibleSprites = self.visibleSprites;
	snapshot.emitters = self.emitters;
	snapshot.particles = self.particles;
	snapshot.drawCalls = self.drawCalls;
	snapshot.textureSwitches = self.textureSwitches;

	[self reset];
	_windowOpen = YES;
	_windowStart = now;
	return snapshot;
}

- (double)percentile95
{
	if (_sampleCount == 0) {
		return 0;
	}
	memcpy(_sortBuffer, _samples, sizeof(double) * _sampleCount);
	qsort(_sortBuffer, _sampleCount, sizeof(double), compareSamples);
	NSInteger index = (NSInteger)ceil(_sampleCount * 0.95) - 1;
	if (index < 0) {
		index = 0;
	}
	if (index > (NSInteger)_sampleCount - 1) {
		index = (NSInteger)_sampleCount - 1;
	}
	return _sortBuffer[index];
}

@end
