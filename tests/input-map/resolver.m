#import <Foundation/Foundation.h>
#import "TGInputResolver.h"
#define CHECK(x) do {if(!(x)) { NSLog(@"failed line %d",__LINE__);return 1;}}while(0)
int main(void) { @autoreleasepool {
 NSMutableArray *events=[NSMutableArray array];
 TGInputResolver *r=[[TGInputResolver alloc] initWithListener:^(NSString *action,NSString *context,BOOL down){[events addObject:@[action,context,@(down)]];}];
 NSDictionary *map=@{@"gameplay":@{@"fire":@[@{@"device":@"keyboard",@"code":@"Space"},@{@"device":@"mouse",@"button":@"left"},@{@"device":@"gamepad",@"button":@"a"}]}};
 [r setMap:map];
 [r transition:@"keyboard" identity:@"1" code:@"Space" down:YES];[r transition:@"keyboard" identity:@"1" code:@"Space" down:YES];
 [r transition:@"mouse" identity:@"1" code:@"left" down:YES];[r transition:@"keyboard" identity:@"1" code:@"Space" down:NO];CHECK(events.count==1);
 [r transition:@"mouse" identity:@"1" code:@"left" down:NO];CHECK(events.count==2);
 [r transition:@"gamepad" identity:@"1" code:@"a" down:YES];[r transition:@"gamepad" identity:@"2" code:@"a" down:YES];
 [r releaseDevice:@"gamepad" identity:@"1"];CHECK(events.count==3);[r releaseDevice:@"gamepad" identity:@"2"];CHECK(events.count==4);
 [r transition:@"keyboard" identity:@"1" code:@"Space" down:YES];[r setContext:nil];CHECK(events.count==6);
 [r setContext:@"gameplay"];[r transition:@"keyboard" identity:@"1" code:@"Space" down:YES];CHECK(events.count==6);
 [r transition:@"keyboard" identity:@"1" code:@"Space" down:NO];[r transition:@"keyboard" identity:@"1" code:@"Space" down:YES];CHECK(events.count==7);
 @try {[r setMap:@{@"gameplay":@{@"fire":@[@{@"device":@"mouse",@"button":@"bad"}]}}];return 1;}@catch(NSException *e){}
 CHECK(events.count==7);[r setMap:map];CHECK(events.count==8);
 [r transition:@"keyboard" identity:@"1" code:@"Space" down:YES];CHECK(events.count==8);
 [r transition:@"keyboard" identity:@"1" code:@"Space" down:NO];[r transition:@"keyboard" identity:@"1" code:@"Space" down:YES];[r releaseAll];CHECK(events.count==10);
 NSLog(@"TGInputResolver: aggregation, repeat, devices, context, invalid map, replacement, release passed");
 }return 0;}
