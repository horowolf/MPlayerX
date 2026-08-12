/*
 * MPlayerX - OpenURLController.m
 *
 * Copyright (C) 2009 - 2011, Zongyao QU
 * 
 * MPlayerX is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 * 
 * MPlayerX is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with MPlayerX; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

#import "UserDefaults.h"
#import "LocalizedStrings.h"
#import "OpenURLController.h"
#import "PlayerController.h"

NSString * const kBookmarkURLKey	= @"Bookmark:URL";

NSString * const kStringURLSchemaHttp	= @"http";
NSString * const kStringURLSchemaHttps	= @"https";
NSString * const kStringURLSchemaFtp	= @"ftp";
NSString * const kStringURLSchemaMms	= @"mms";
NSString * const kStringURLSchemaRtsp	= @"rtsp";
NSString * const kStringURLSchemaRtp	= @"rtp";
NSString * const kStringURLSchemaUdp	= @"udp";


@implementation OpenURLController

+(void) initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:
	 [NSDictionary dictionaryWithObjectsAndKeys:
	  [NSNumber numberWithBool:YES], kUDKeyFFMpegHandleStream,
	  nil]];
}

-(void) initURLList:(NSDictionary*)list
{
	[urlBox removeAllItems];
	
	NSArray *urls = [list objectForKey:kBookmarkURLKey];

	if (urls) {
		[urlBox addItemsWithObjectValues:urls];
	}
	
	[urlBox addItemWithObjectValue:kMPXStringURLPanelClearMenu];
}

-(void) addUrl:(NSString*)urlString
{
	NSInteger idx = [urlBox indexOfItemWithObjectValue:urlString];
	
	if (idx != 0) {
		// if it doesn't exist, or isn't in the first position
		if (idx != NSNotFound) {
			// if this string was already there, remove it and then add it at the first position
			[urlBox removeItemAtIndex:idx];
		}

		[urlBox insertItemWithObjectValue:urlString atIndex:0];	
	}
}

-(void) syncToBookmark:(NSMutableDictionary*)bmk
{
	NSArray *urls = [urlBox objectValues];
	
	[bmk setObject:[urls subarrayWithRange:NSMakeRange(0, [urls count]-1)] forKey:kBookmarkURLKey];
}

-(IBAction) urlSelected:(id)sender
{
	if ([sender indexOfSelectedItem] == ([[sender objectValues] count]-1)) {
		[sender removeAllItems];
		[sender addItemWithObjectValue:kMPXStringURLPanelClearMenu];
		[sender setStringValue:@""];
	}
}

-(IBAction) openURL:(id) sender
{
	// since this is a modal method, it is safe to set the cmdOptionalText
	if ([[NSUserDefaults standardUserDefaults] boolForKey:kUDKeyFFMpegHandleStream]) {
		[cmdOptionalText setStringValue:kMPXStringUseMPlayerHandleStream];
	} else {
		[cmdOptionalText setStringValue:kMPXStringUseFFMpegHandleStream];
	}

	if ([NSApp runModalForWindow:openURLPanel] == NSFileHandlingPanelOKButton) {
		// mplayer's online playback feature is currently not very stable and freezes often, so disable this feature for now
		[playerController loadFiles:[NSArray arrayWithObject:[urlBox stringValue]] fromLocal:NO];
	}
}

-(IBAction) confirmed:(id) sender
{
	NSURL *url = [NSURL URLWithString:[urlBox stringValue]];

	NSString *scheme = [[url scheme] lowercaseString];
	
	if (scheme && 
		([scheme isEqualToString:kStringURLSchemaHttp] || [scheme isEqualToString:kStringURLSchemaFtp] || 
		 [scheme isEqualToString:kStringURLSchemaRtsp] || [scheme isEqualToString:kStringURLSchemaMms] ||
		 [scheme isEqualToString:kStringURLSchemaHttps]|| [scheme isEqualToString:kStringURLSchemaRtp] ||
		 [scheme isEqualToString:kStringURLSchemaUdp])) {
		// fix up the URL first
		[urlBox setStringValue:[[url standardizedURL] absoluteString]];
		// exit Modal mode
		[NSApp stopModalWithCode:NSFileHandlingPanelOKButton];
		// hide the window
		[openURLPanel orderOut:self];
	} else {
		NSBeginAlertSheet(kMPXStringError, kMPXStringOK, nil, nil, openURLPanel, nil, nil, nil, nil, kMPXStringURLNotSupported);
	}
}

-(IBAction) canceled:(id) sender
{
	[NSApp abortModal];
	[openURLPanel orderOut:self];
}

@end
