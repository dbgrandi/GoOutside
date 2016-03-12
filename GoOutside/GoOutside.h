//  Created by David Grandinetti on 3/12/16.
//  Copyright © 2016 dbgrandi. All rights reserved.
//

#import <AppKit/AppKit.h>

@interface GoOutside : NSObject

+ (instancetype)sharedPlugin;

@property (nonatomic, strong, readonly) NSBundle* bundle;
@end