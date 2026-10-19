#import "TGInputResolver.h"
@implementation TGInputResolver {
 TGInputListener _listener;
 NSDictionary *_map;
 NSString *_context;
 NSMutableDictionary<NSString *,NSString *> *_held;
 NSMutableDictionary<NSString *,NSMutableSet<NSString *> *> *_active;
}
- (instancetype)initWithListener:(TGInputListener)listener
{
 if (self=[super init]) { _listener=[listener copy];_map=@{};_context=@"gameplay";_held=[NSMutableDictionary dictionary];_active=[NSMutableDictionary dictionary]; }
 return self;
}
static void TGInvalidInput(void) { [NSException raise:NSInvalidArgumentException format:@"Invalid inputMap: expected contexts, actions and digital bindings"]; }
- (void)setMap:(id)value
{
 if (![value isKindOfClass:[NSDictionary class]]) TGInvalidInput();
 NSMutableDictionary *next=[NSMutableDictionary dictionary];
 NSRegularExpression *codes=[NSRegularExpression regularExpressionWithPattern:@"^(Key[A-Z]|Digit[0-9]|F([1-9]|1[0-2])|Arrow(Up|Down|Left|Right)|Space|Escape|Enter|Tab|Backspace|Delete|Home|End|PageUp|PageDown|Shift(Left|Right)|Control(Left|Right)|Alt(Left|Right)|Meta(Left|Right))$" options:0 error:nil];
 NSArray *pad=@[@"a",@"b",@"x",@"y",@"l1",@"r1",@"l2",@"r2",@"l3",@"r3",@"start",@"select",@"home",@"up",@"down",@"left",@"right"];
 for (id ctx in value) {
  if (![ctx isKindOfClass:[NSString class]] || ![ctx length] || ![value[ctx] isKindOfClass:[NSDictionary class]]) TGInvalidInput();
  NSMutableDictionary *actions=[NSMutableDictionary dictionary];
  for (id action in value[ctx]) {
   id bindings=value[ctx][action];
   if (![action isKindOfClass:[NSString class]] || ![action length] || ![bindings isKindOfClass:[NSArray class]]) TGInvalidInput();
   NSMutableArray *copy=[NSMutableArray array];
   for (id b in bindings) {
    if (![b isKindOfClass:[NSDictionary class]] || [b count]!=2) TGInvalidInput();
    NSString *device=b[@"device"];BOOL keyboard=[device isEqual:@"keyboard"];
    id code=b[keyboard?@"code":@"button"];
    if (![code isKindOfClass:[NSString class]]) TGInvalidInput();
    BOOL valid=keyboard ? [codes numberOfMatchesInString:code options:0 range:NSMakeRange(0,[code length])]==1 : [device isEqual:@"mouse"] ? [@[@"left",@"middle",@"right"] containsObject:code] : [device isEqual:@"gamepad"] && [pad containsObject:code];
    if (!valid) TGInvalidInput();
    [copy addObject:@{@"device":[device copy],keyboard?@"code":@"button":[code copy]}];
   }
   actions[[action copy]]=[copy copy];
  }
  next[[ctx copy]]=[actions copy];
 }
 @synchronized(self) { [self releaseActions];_map=[next copy]; }
}
- (NSDictionary *)map { @synchronized(self) { return _map; } }
- (NSString *)context { @synchronized(self) { return _context; } }
- (void)setContext:(NSString *)context
{
 @synchronized(self) { if ([_context isEqual:context] || (!_context && !context)) return;[self releaseActions];_context=[context copy]; }
}
- (void)releaseActions
{
 NSArray *old=_active.allKeys;[_active removeAllObjects];
 for (NSString *action in old) _listener(action,_context,NO);
}
- (BOOL)transition:(NSString *)device identity:(NSString *)identity code:(NSString *)code down:(BOOL)down
{
 @synchronized(self) {
  NSString *source=[NSString stringWithFormat:@"%@:%@:%@",device,identity,code];
  if (down) {
   if (_held[source]) return NO;
   _held[source]=code;
   NSDictionary *actions=_context?_map[_context]:nil;
   for (NSString *action in actions) {
    BOOL matches=NO;
    for (NSDictionary *b in actions[action]) if ([b[@"device"] isEqual:device] && [b[[device isEqual:@"keyboard"]?@"code":@"button"] isEqual:code]) {matches=YES;break;}
    if (!matches) continue;
    BOOL first=!_active[action];
    if (first) _active[action]=[NSMutableSet set];
    [_active[action] addObject:source];
    if (first) _listener(action,_context,YES);
   }
  } else {
   if (!_held[source]) return NO;
   [_held removeObjectForKey:source];
   for (NSString *action in _active.allKeys) {
    NSMutableSet *sources=_active[action];
    if ([sources containsObject:source]) {
     [sources removeObject:source];
     if (!sources.count) {[_active removeObjectForKey:action];_listener(action,_context,NO);}
    }
   }
  }
  return YES;
 }
}
- (void)releaseDevice:(NSString *)device identity:(NSString *)identity
{
 @synchronized(self) {
  NSString *prefix=[NSString stringWithFormat:@"%@:%@:",device,identity];
  for (NSString *source in _held.allKeys) if ([source hasPrefix:prefix]) [self transition:device identity:identity code:_held[source] down:NO];
 }
}
- (void)releaseAll { @synchronized(self) { [self releaseActions];[_held removeAllObjects]; } }
@end
