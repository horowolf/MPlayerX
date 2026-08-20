/*
 * MPlayerX - LogAnalyzer.m
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

#import "LogAnalyzer.h"
#import "LogAnalyzeOperation.h"

@implementation LogAnalyzer

@synthesize delegate;

-(id) init
{
	self = [super init];

	if (self) {
		// Queue for parsing the log. This has to happen in -init, not only in
		// -initWithDelegate:, or a plain [[LogAnalyzer alloc] init] silently
		// leaves queue == nil -- and since -addOperation: on nil is a no-op,
		// every line of mplayer's output would be dropped without a single
		// error: no playback state, no time updates, no track info.
		queue = [[NSOperationQueue alloc] init];
	}
	return self;
}

-(id) initWithDelegate:(id<LogAnalyzerDelegate>) obj
{
	self = [self init];

	if (self) {
		delegate = obj;
	}
	return self;
}

-(void) dealloc
{
	[self stop];

	[queue release];	
	[super dealloc];
}

-(void) stop
{
	[queue cancelAllOperations];
	[queue waitUntilAllOperationsAreFinished];
}

-(void) analyzeData:(NSData*) data
{
	if (data && ([data length] != 0) && delegate) {
		// If there's no delegate, do nothing
		// Therefore this class must have a delegate to work properly
		LogAnalyzeOperation *op = [[LogAnalyzeOperation alloc] initWithData:data 
														 whenFinishedTarget:delegate 
																   selector:@selector(logAnalyzeFinished:)];		
		[queue addOperation:op];
		[op release];
	}
}
@end
