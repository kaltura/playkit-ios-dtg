//
//  ObjCUtils.h
//  DownloadToGo
//
//  Created by Noam Tamim on 20/02/2019.
//

#import <Foundation/Foundation.h>

NSDictionary<NSString*,NSString*> * _Nonnull parseM3U8Attributes(NSString* _Nonnull str, NSString* _Nonnull prefix);
NSString* _Nonnull md5WithString(NSString* _Nonnull str);
