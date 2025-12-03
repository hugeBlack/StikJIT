//
//  ProcessInspectorBridge.h
//  StikJIT
//

#import "../idevice/JITEnableContext.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSArray<NSDictionary*> * _Nullable FetchDeviceProcessList(NSError **error);
FOUNDATION_EXPORT BOOL KillDeviceProcess(int pid, NSError **error);

NS_ASSUME_NONNULL_END
