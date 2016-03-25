//  Created by David Grandinetti on 3/12/16.
//  Copyright © 2016 dbgrandi. All rights reserved.
//

#import "GoOutside.h"

static GoOutside *sharedPlugin;

// Thanks to @alloy for writing AxeMode!
// Most of this was lifted from https://github.com/alloy/AxeMode/blob/master/AxeMode/AxeMode.m

//@interface IDEWorkspace : IDEXMLPackageContainer
@interface IDEWorkspace : NSObject
@end

@interface IDEWorkspaceArena : NSObject
@property(readonly) IDEWorkspace *workspace;
@end

@interface IDESchemeCommand : NSObject
@property(readonly, nonatomic) NSString *commandNameGerund;
@property(readonly, nonatomic) NSString *commandName;
@end

@interface IDEActivityLogSection : NSObject
@property(readonly) unsigned long long totalNumberOfErrors;
@property(readonly) NSArray *subsections;
@property(readonly) NSString *text;
// TODO use this instead?
- (id)enumerateSubsectionsRecursivelyUsingPreorderBlock:(id)arg1;
@end

@interface IDEBuildParameters : NSObject
@property(readonly) IDESchemeCommand *schemeCommand;
@end

@interface IDEBuildOperation : NSObject
@property(readonly) IDEBuildParameters *buildParameters;
@property(readonly) int purpose;
@end

@interface IDEExecutionEnvironment : NSObject
@property(readonly) IDEActivityLogSection *latestBuildLog;
@property(readonly) IDEWorkspaceArena *workspaceArena;
@end

NS_ENUM(NSInteger, AXELastBuildType){
    AXELastBuildTypeRun,
    AXELastBuildTypeTest,
    AXELastBuildTypeProfile,
    AXELastBuildTypeAnalyze,
    AXELastBuildTypeArchive
};

@interface GoOutside()
@property (nonatomic, strong, readwrite) NSBundle *bundle;
@property (nonatomic, assign, readwrite) enum AXELastBuildType lastBuildType;
@property (nonatomic, strong, readwrite) NSDate *lastBuildStart;
@end

@implementation GoOutside

+ (void)pluginDidLoad:(NSBundle *)plugin
{
    static dispatch_once_t onceToken;
    NSString *currentApplicationName = [[NSBundle mainBundle] infoDictionary][@"CFBundleName"];
    if ([currentApplicationName isEqual:@"Xcode"]) {
        dispatch_once(&onceToken, ^{
            sharedPlugin = [[self alloc] initWithBundle:plugin];
        });
    }
}

+ (instancetype)sharedPlugin
{
    return sharedPlugin;
}

- (id)initWithBundle:(NSBundle *)plugin
{
    if (self = [super init]) {
        self.bundle = plugin;
        [self setupDefaults];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(xcodeDidFinishLaunching:)
                                                     name:NSApplicationDidFinishLaunchingNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(buildStarted:)
                                                     name:@"IDEBuildOperationWillStartNotification"
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didFinishBuild:)
                                                     name:@"ExecutionEnvironmentLastUserInitiatedBuildCompletedNotification"
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)xcodeDidFinishLaunching: (NSNotification *) notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSApplicationDidFinishLaunchingNotification
                                                  object:nil];
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self createMenuItem];
    }];
}

- (void)createMenuItem
{
    NSMenuItem *menuItem = [[NSApp mainMenu] itemWithTitle:@"Window"];
    if (menuItem) {
        [[menuItem submenu] addItem:[NSMenuItem separatorItem]];
        NSMenuItem *actionMenuItem = [[NSMenuItem alloc] initWithTitle:@"Stats" action:@selector(showStats) keyEquivalent:@""];
        [actionMenuItem setTarget:self];
        [[menuItem submenu] addItem:actionMenuItem];
    }
}

- (void)setupDefaults
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults dictionaryForKey:@"GoOutsideStats"]) {
        NSDictionary *baseGoOutSideStats = @{ @"builds": @0,
                                              @"totalBuildTime": @0 };
        [defaults setObject:baseGoOutSideStats forKey:@"GoOutsideStats"];
    }
}

- (void)showStats
{
    NSDictionary *stats = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"GoOutsideStats"];
    NSNumber *builds = stats[@"builds"];
    NSNumber *buildTime = stats[@"totalBuildTime"];
    NSAlert *alert = [[NSAlert alloc] init];
    NSString *text = [NSString stringWithFormat:@"Hello, developer. You've had %@ builds in Xcode recently that took %@. Go outside and play.", builds, [self textFrom:buildTime]];
    [alert setMessageText:text];
    [alert runModal];
}

- (NSString *)unit:(NSString *)unit withValue:(NSInteger)value
{
    switch (value) {
        case 0:
            return @"";
            
        case 1:
            return [NSString stringWithFormat:@"%td %@", value, unit];
            
        default:
            return [NSString stringWithFormat:@"%td %@s", value, unit];
    }
}

- (NSString *)textFrom:(NSNumber *)buildTime
{
    // set second, minute, hour or more...
    NSArray *units = @[@"second", @"minute", @"hour"];
    NSArray *conversions = @[@(60), @(60), @(NSIntegerMax)];
    
    // get the value from input buildTime
    NSInteger value = [buildTime integerValue];
    
    // calculate and got strings
    NSMutableArray *texts = [NSMutableArray array];
    for (NSInteger index = 0; index < units.count; index++) {
        NSInteger conversion = [conversions[index] integerValue];
        [texts addObject:[self unit:units[index] withValue:value % conversion]];
        if (value >= conversion) {
            value /= conversion;
        } else {
            break;
        }
    }
    
    // reverse and combine strings
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"self.length > 0"];
    NSArray *filterTexts = [texts filteredArrayUsingPredicate:predicate];
    if (filterTexts.count) {
        return [[[filterTexts reverseObjectEnumerator] allObjects] componentsJoinedByString:@", "];
    } else {
        return @"0 second";
    }
}

- (void)buildStarted:(NSNotification *)notification
{
    IDEBuildOperation *operation = (IDEBuildOperation *)notification.object;
    NSString *typeOfOperation = [[[operation buildParameters] schemeCommand] commandName];

    if ([typeOfOperation isEqualToString:@"Test"]) {
        self.lastBuildType = AXELastBuildTypeTest;
    } else if ([typeOfOperation isEqualToString:@"Archive"]) {
        self.lastBuildType = AXELastBuildTypeArchive;
    } else if ([typeOfOperation isEqualToString:@"Profile"]) {
        self.lastBuildType = AXELastBuildTypeProfile;
    } else if ([typeOfOperation isEqualToString:@"Analyze"]) {
        self.lastBuildType = AXELastBuildTypeProfile;
    } else {
        self.lastBuildType = AXELastBuildTypeRun;
    }
    self.lastBuildStart = [NSDate date];
}

- (void)incrementBuildCount
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *stats = [[defaults dictionaryForKey:@"GoOutsideStats"] mutableCopy];
    NSUInteger buildCount = [stats[@"builds"] unsignedIntegerValue];
    stats[@"builds"] = @(buildCount + 1);
    [defaults setObject:stats forKey:@"GoOutsideStats"];
}

- (void)addBuildTime:(NSTimeInterval)seconds
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *stats = [[defaults dictionaryForKey:@"GoOutsideStats"] mutableCopy];
    NSNumber *totalBuildTime = stats[@"totalBuildTime"];
    NSTimeInterval totalBuildTimeInterval = [totalBuildTime doubleValue];
    stats[@"totalBuildTime"] = @(totalBuildTimeInterval + seconds);
    [defaults setObject:stats forKey:@"GoOutsideStats"];
}

- (void)didFinishBuild:(NSNotification *)notification
{
    [self incrementBuildCount];

    NSTimeInterval buildTime = [self.lastBuildStart timeIntervalSinceNow];
    [self addBuildTime:-buildTime];
}

@end
