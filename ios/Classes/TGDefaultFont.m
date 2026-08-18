#import "TGDefaultFont.h"
#import "TGBitmapFont.h"
#import <UIKit/UIKit.h>

static const int kCharWidth = 9;
static const int kCharHeight = 15;

static NSString *const kPngBase64 = @""
	@"iVBORw0KGgoAAAANSUhEUgAAAJAAAABaCAYAAABXNd9qAAAGD0lEQVR42u1dy5LjMAhUu/z/v9x7"
	@"2UM268g89bBR1VxmMnYkIUDQNCDZatSwjmOD7/hECedT5nUkTP7z773P8kZI7p7z63e/nsOgTb2b"
	@"09NV+j9zHKGBYNAwks3G3x8qnsPkOeHmPbw4ODsKI2aaMP7YdHa+KASCKNnY2eb0ah7YTPts5QOx"
	@"sxH80ERc8XS+wac7khYQncWEQMNAsOh3/3NlUqDUDpnaCh0zKzVz0w/IOVmjsLPBuPgMOs+k0Beh"
	@"03QgcAMweL0RfSB2uMZrNgWDhCB7LkjUjKHjnLTR374LftyypKdCommiTAE3cnyh1C7Q/v1s+wcQ"
	@"0VHXM/0HDPh/ztaoxwKCAcHiQehYWx3XipwbhRQb5MJWMxl332ekVnilBhptCkZqmRkbOnV9UNn4"
	@"Gk/XQDVKgGo8dZyGqCVvPiN5jiZCSkOKQ/M+Cv2L6Hm1jZOo/2XjpVAIBkAzLNfv2dfqFecV8S56"
	@"534a4iQwnFp20g00TpAK7QXFLYaK5Kw11kSn5vVgqrRR/+5+HU2OFJTkZCLxOEzA8nDRUx4xJ8s6"
	@"udM8p1HLrJwlhuBQaHM+uEEOZKEeKZiP99BCKIyX7zwTTwuVOR0EmR6JWYmIbvMia07hIRyBGuCI"
	@"HN2ZFNmk4nRofCDvxsMYRabQv8GgqPQv0wOnoEErzKcDwbdsfmaAP/INqZ21RlCGM7xW4lYD0bkJ"
	@"FPgmNKhuKjWX1k9iwHOYZII8xQTpebRDAamYUSbjfQ6U79I4pNgY9VjJ1BcM7iCIlQsrKEsJUAlP"
	@"CVCNVnCOGu3dcA5pUImG6zCE4QBNXIOOIKX1+8AZXGyK8AQEBZOaZ98VXkIRMrmEc3wyXiAZnsCF"
	@"asoZFMPJ9lkwKXgqhnPgB3UKnJP9jthaAmS9HFZUoA2BEepRKaEW/J3Ve3r8iB5zUMXjo24km8eB"
	@"XHCO75NDZ40UFytUpMG38aQ8VgoFeHBQt0J8OB2+Gu3dMafDmEylkGFiRCkxLt4n/QwMkIZRbBmY"
	@"kG9UJ8CPThbdmqGuevP2zjgQLm5LMMZZaLDLI0qERlZv0FGGJMUdMQA14PI1j47AIJHVCwvdxBB8"
	@"5c6GCI/2g7pC+QnnYF2fa3hNWI0alUytUQJUowSoRtubQEHlA9FYvBfFlqEJnEkhFhRUeGg+I3lX"
	@"JOSDATVnNDCghGogSUcdK7l42ySSKyk0xODUT1aEn15AGQyArR7Egs64wyqElVcBvYhYFpPjXzBS"
	@"8mzhA7HtCZGgQitkJqcjtZA5b3ncNGezljrTCTldtUPQ0zrycIdbGIRmcIYfhEVbC4xM78Cj1Q4H"
	@"7CECQoqJznUzAuC9vkuGX8fgw40VNBCC4bGZi8wFbkDtCWU9I9jFmFx1gAS2tSitQSMHYgQovs2O"
	@"RHsYKjK0UDRjBgwlSCtpIe7GzlEY6T2qMlL36XxZA7a3CVI2Ky3OqtWqEWXCyiTVCAHVM+BGhAV9"
	@"As/tkcbSGEsqg4bs+TIN5/Dwto1FPjXAiX6yCcNC78AgUoRlAol0xE7gpN5FEH0vhe+iAVDHwLVp"
	@"zoAjje3X1UDCIwhYFW1SrK2UIpqhrBocxCTzrmr3FAWIiuYHsr4Lht4bNPIeIbH1OIL4iiJAgv98"
	@"5nyAM8pJhEvFE600YZV9rhtkSCpjNUThU2+NCG5PtSycQ3vT8LBztM3YOdqA9lSjzN1Pdo4RbA7N"
	@"CbtwI+eSmUOsVDdWABsHmjsxO0eNOScab0MkvsVJRaVUqjZ+dcccb8REl7DUjbE00IPML0uAFl6g"
	@"zeefvn6lgSqaHeIDWdL6ELQUorHDMQ1tkTy8PugUC0jaJGXyAy1dM3YEQywwKdgV4bB+qnsqMT/Y"
	@"nGCB1u99JnD/QAmfkJwcTA7e4UK4LMjD1fKIEmL5NB8ogteGA/poRHQujKzClQDFOMkP4i5ONF4C"
	@"FcHiGO1v7ajOLx6TFxcToJkR9C4RTCAYJFhDS5u9EAsKyp4Z7HcwiScQN7dPGphAOBjv3FZm50Cg"
	@"7Y1g5/DCSCK7VL+mwvcMttnRzW0RJERwPCOyhVLlwmqI4ilYhAuaJUCtkAJtYRTAH7U7bOeOXZ6i"
	@"AAAAAElFTkSuQmCC";

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
