//
//  ProcessInspectorBridge.m
//  StikJIT
//

#import "ProcessInspectorBridge.h"

NSArray<NSDictionary*> * _Nullable FetchDeviceProcessList(NSError **error) {
    @try {
        return [[JITEnableContext shared] fetchProcessListWithError:error];
    } @catch (NSException *exception) {
        if (error) {
            NSString *message = [NSString stringWithFormat:@"Process fetch failed: %@", exception.reason ?: @"Unknown error"];
            *error = [NSError errorWithDomain:@"ProcessInspectorBridge"
                                         code:-500
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }
}

BOOL KillDeviceProcess(int pid, NSError **error) {
    @try {
        return [[JITEnableContext shared] killProcessWithPID:pid error:error];
    } @catch (NSException *exception) {
        if (error) {
            NSString *message = [NSString stringWithFormat:@"Process kill failed: %@", exception.reason ?: @"Unknown error"];
            *error = [NSError errorWithDomain:@"ProcessInspectorBridge"
                                         code:-501
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }
}
