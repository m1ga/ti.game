#import "TGDefaultFont.h"
#import "TGBitmapFont.h"
#import <UIKit/UIKit.h>

static const int kCharWidth = 9;
static const int kCharHeight = 15;

static NSString *const kPngBase64 = @""
	@"iVBORw0KGgoAAAANSUhEUgAAAJAAAAB4CAYAAAAdUXtXAAAGvUlEQVR42u1d247jOgwTi/z/L/M8"
	@"7e6cThLrZidpSWCAQes6cUxfItESSJogZPHSIxBEIEEEEr6DQPzxd/a9nZTzlPlZ1hzXOipPxzXM"
	@"WcYC7fp08KoZiI7/PSSjmWHw2Z/fwEHG6P1j5zsESc/EALkLeXAVgeD4/72TcNBhfOs0LCI/HO2j"
	@"83s8cOb53z1vDUTwECRa9/tIHREOjnqQaM+s2feMlEwQN7L8o4s8FQKtmqn4RgQMZqGjUc63unBx"
	@"myywFKJ5kLeRJ7OEoXhjdP4/moGiS1jHUufd45x1Xue+rGuP5NmLHT4zBC3RHWv3+8wweuBwfH5G"
	@"su7ROboWFr+QYGI9wwEHuTIe/Rp9+SZ8U188EpAlWjC5MgQRSI9AEIEEEUgQgYQvxHZgdEPB8DR6"
	@"5YwY9zhwuEbr8NYzKpdtu93MJsRAf++2aztwCzDwkEaOQQY8795reTvI+3CjzkyPJfzMf1cZpJ0G"
	@"RST7+2/57WB0HVWKwOhn0YQ+up53dol44UtmfbuPNZqBNo9IdDrAwH++DCQ6N9qpmY7PjsaoH4zJ"
	@"+53pd1vpykjNjNtkzYuX0XTMYNkZoLqs7ElG6NA/sbOjmpaejknhl6AMjr1KlDxoUPV5RFerlxQ0"
	@"LM+d93K21ZihtDz1xrM4RWffaLKjMfvG17Ese66FRcvT7LewU25IziGYDImCCCSIQIIIJAgikCAC"
	@"CSKQYN8k52BRXjFbYoGEqZ4Ja7f3hCiLEpOI3y9jiWfSx8hof2zJw3scnEk/8z3tNeTMHO+91mzJ"
	@"R9TNgRs4TelUNCAr0Xk5Y+nsRczIHM09ckKiwf/06AN6C06eVsu4DhaioaO4UJVXlY50LNF3Jg8c"
	@"sxCscM5+O7hxFpjqkU/YwhOaSDzwjEN4STwem+vZL72FYefvKDpHZ4QLFiNerJBn2IIoGLPICpt4"
	@"XHo7YR8mLSt7UyaK+qLKfaMpVAod+0YGRXd0RCmZuV0Y3rPkHILJkCiIQIIIJIhAgiACCSKQIAIJ"
	@"9i1yDjZIHqyxnmyqABbL8CD0cFZiwUZ5CRLuDQaPdKcMkZvThxWJPtFRz9NzSnQEn7BBCgc0B0ZP"
	@"+S1fN3mweEDHc0KwdSuc92fzs0/1w2txchHsaI9m+1LY4JREMN0Tiz6+lSSaEqEs6sCMPCAceKkx"
	@"UaLgddyyONVjEXmiy9mSt7CRlMOb0gnORHJX7DsyESi61Zjde7pLZ6JXYgpnQXyFA/ksCksKnUuL"
	@"5zss2rR7l3AGNtuXDFbJOYSsVhpKtiKUVYqyRAtyZQgikCACCSKQIIhAgl2YM5ULw9PaRdmiZ8RR"
	@"tqY8F5Fr8Q45VLe7+Vbs+VmOp54EvbMztesUKBvSPbHo7Y9m3rGmQOJsCOLQQf7KM0Ym3VNWENUh"
	@"KLNEJ3cJ07KEymQzypRjk2YIswSAW3OcmTv5aj7FB4UnbaIrs4Ld0VezKLDCTBXkrfekW+OD9kSf"
	@"OKsHzdeaqVXOROfozMjDRS8Jis7RtBlfnU/NnmoHMkkWPuZaJku0IAIJIpAgiECCCCSIQIIIZMtt"
	@"NN9sqKqcG5vx7KgZ6HskKN1B1HddKtX4QDbI6NOVzml2zJ5qfKBImTsZGKPyk18kep2kMeDBw4BT"
	@"w7JXls5z+O+fXxkCpiu8y1F7sTAFlSedl3fwTl3CEDjTzge5O1ZJa7uWn2jMgFFut1/35Q3v0il7"
	@"WBXeJZKXI9IRR8I1z/O5q84HltRdbYFKOmQPbNoDIBm5AgO5hGcvg4H6cbSPi8RRqgwuNsch2m0H"
	@"+E/PgQ/K9vfpspD7TF3SAwkmS7QgAgkikCACCYIIJIhAwoMJlD2X3lnmp5GQgXJX3vMd2+51FzF7"
	@"P+92IAYcpSvKeH7vPW9/p3atbLvNNiQyY8K2nFRjhjQCwePXmGRBvqLt3dFCwimhMr6waKSL2We7"
	@"6fBqd6SxooOEK9s+ulbX7HTqSN4+5NgtrRa9g08J6NQQDCPiFB86kreHO/7gzLDTrQb4hFQFLfWs"
	@"3gN1lfHsiWbf88p6KnLeyj5peC154wUZEgURSBCBBBFIEEQgQQQSRCDhuwjkkRB0lfGcTI1e66hc"
	@"9z1bk4zDG3WDC2Ql9rRjPZxwXHjlvVekGnQcdvSUWSkdMU+Y31UuiJZU083uBa853wJuEzq/P+tg"
	@"r0DO8/tpg/ToZGomKUom5Eo1Z1Y2kQqK9WS83131RGepqSS6OtkKnPoba0iEtyLKPBfU4z2rz09P"
	@"tjJam3Gz6PC4WRneITnOn030FZIGJBp6hVSjcj9d7UJhmZuqfZKcQ5AhURCBBBFI+Eb8B4v1fZB6"
	@"jeGcAAAAAElFTkSuQmCC";

@implementation TGDefaultFont

+ (TGBitmapFont *)makeFont
{
	// The loader singleton stays retained here forever — the sheet only
	// holds it weakly (the proxy-owns-loader pattern of the sprite
	// sheets); it is stateless, so every font instance can share it.
	static TGDefaultFont *loader;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		loader = [[TGDefaultFont alloc] init];
	});
	TGSpriteSheet *sheet = [[TGSpriteSheet alloc] initWithLoader:loader
												  gridFrameWidth:kCharWidth
												 gridFrameHeight:kCharHeight];
	sheet.smoothing = NO; // pixel font — keep it crisp when scaled
	NSMutableString *characters = [NSMutableString string];
	for (unichar c = 32; c < 127; c++) {
		[characters appendFormat:@"%C", c];
	}
	[characters appendString:@"ÁÉÍÓÚÜÑáéíóúüñ¿¡ÄÖäößËÏëïÈèÊêÀà"];
	return [TGBitmapFont gridFontWithSheet:sheet
								characters:characters
								 charWidth:kCharWidth
								charHeight:kCharHeight];
}

#pragma mark TGSpriteSheetLoader — called from the render thread on first use

- (UIImage *)loadSpriteSheet:(TGSpriteSheet *)sheet
{
	NSData *png = [[NSData alloc] initWithBase64EncodedString:kPngBase64
														  options:0];
	return (png != nil) ? [UIImage imageWithData:png] : nil;
}

@end
