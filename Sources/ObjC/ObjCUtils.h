//
//  ObjCUtils.h
//  DownloadToGo
//
//  Created by Noam Tamim on 20/02/2019.
//

#import <Foundation/Foundation.h>

NSDictionary<NSString*,NSString*> * _Nonnull parseM3U8Attributes(NSString* str, NSString* prefix);
NSString* md5WithString(NSString* str);
