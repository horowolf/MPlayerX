/*
 * MPlayerX - PlayerCore.m
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
#import "PlayerCore.h"
#import "CocoaAppendix.h"

#define kPlayerCoreTermNormal		(0)

@interface PlayerCore (PlayerCoreInternal)
-(void) readOutput:(NSNotification*)notification;
-(void) readError:(NSNotification*)notification;
-(void) taskHasTerminated:(NSNotification*)notification;
@end

@implementation PlayerCore

@synthesize delegate;

#pragma mark Init/Dealloc
-(id) init 
{
	self = [super init];
	
	if (self) {
		delegate = nil;
		task = nil;
		runningModes = [[NSArray alloc] initWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode, nil];
	}
	return self;
}

-(void) dealloc
{
	// The terminate function calls the delegate's functions, which could cause logic errors
	delegate = nil;

	[self terminate];
	[runningModes release];
	
	[super dealloc];
}

#pragma mark Function
- (void) terminate
{
	if (task) {
		// To prevent the function from running multiple times
		NSTask *backup = task;
		task = nil;
		
		if ([backup isRunning]) {
			[backup terminate];
			[backup waitUntilExit];
		}
		[backup release];
	}
}

- (BOOL) playMedia: (NSString *) moviePath withExec: (NSString *) execPath withParams: (NSArray *) params
{
	if (moviePath && execPath) {
	
		[self terminate];
		
		// Create the task
		task = [[NSTask alloc] init];
		// Associate input/output
		[task setStandardInput:[NSPipe pipe]];
		[task setStandardOutput:[NSPipe pipe]];
		[task setStandardError: [NSPipe pipe]];
		// Specify the path of the exec to run
		[task setLaunchPath: execPath];
		// Create argv
		if (params) {
			[task setArguments: [params arrayByAddingObject:moviePath]];
		} else {
			[task setArguments: [NSArray arrayWithObject:moviePath]];
		}
		
		MPLog(@"%@", [[task arguments] componentsJoinedByString:@"\n"]);
		
		// Set environment parameters
		NSMutableDictionary *env = [[[NSProcessInfo processInfo] environment] mutableCopy];
		[env setObject:@"1" forKey:@"DYLD_BIND_AT_LAUNCH"]; //delete the message for DYLD
		[env setObject:@"xterm" forKey:@"TERM"]; // delete the message from mplayer about the "unknown" terminal
		[env removeObjectForKey:@"MPLAYER_HOME"];
		[env removeObjectForKey:@"HOME"];
		[task setEnvironment:env];
		[env autorelease];
		
		[task setCurrentDirectoryPath:[execPath stringByDeletingLastPathComponent]];
		
		// Set up the notification/listening mechanism
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(readOutput:)
													 name:NSFileHandleReadCompletionNotification
												   object:[[task standardOutput] fileHandleForReading]];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(readError:)
													 name:NSFileHandleReadCompletionNotification
												   object:[[task standardError] fileHandleForReading]];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(taskHasTerminated:)
													 name:NSTaskDidTerminateNotification
												   object:task];
		
		[[[task standardOutput] fileHandleForReading] readInBackgroundAndNotifyForModes:runningModes];
		[[[task  standardError] fileHandleForReading] readInBackgroundAndNotifyForModes:runningModes];

		// Launch the task
		[task launch];
		return YES;
	}
	return NO;
}

- (BOOL) sendStringCommand: (NSString *) cmd
{
	if (task && [task isRunning]) {
		// MPLog(@"%@",cmd);
		[[[task standardInput] fileHandleForWriting] writeData:[cmd dataUsingEncoding:NSUTF8StringEncoding]];
		return YES;
	}
	return NO;
}

#pragma mark Internal 
-(void) readOutput:(NSNotification*)notification
{
	if (task && [task isRunning]) {
		NSData *data = [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];
		
		if (([data length] != 0) && delegate) {
			[delegate playerCore:self outputAvailable:data];
		}
		[[[task standardOutput] fileHandleForReading] readInBackgroundAndNotifyForModes:runningModes];
	}
}

-(void) readError:(NSNotification*)notification
{
	if (task && [task isRunning]) {
		NSData *data = [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];

		if (([data length] != 0) && delegate) {
			[delegate playerCore:self errorHappened:data];
		}
		[[[task  standardError] fileHandleForReading] readInBackgroundAndNotifyForModes:runningModes];
	}
}

-(void) taskHasTerminated:(NSNotification*)notification
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	// Get the return status; 0 means normal exit
	// At this point the task variable may have become nil
	if (delegate) {
		[delegate playerCore:self hasTerminated:([[notification object] terminationStatus] != kPlayerCoreTermNormal)];
	}
}
@end
