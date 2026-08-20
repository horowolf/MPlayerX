/*
 * MPlayerX - CoreControllerVOProto.m
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

// The half of CoreController that the mplayer child process talks to over
// Distributed Objects. CoreController itself is Swift, but this surface can't
// be: both halves of the DO handshake depend on details Swift cannot express.
//
//  1. mplayer opens with
//     `[proxy conformsToProtocol:@protocol(MPlayerOSXVOProto)]`. Answering
//     that means DO has to resolve a Protocol object *in this process* from
//     the name on the wire, and a Swift `@objc protocol` is registered under a
//     mangled name (_TtP8MPlayerXP33_...17MPlayerOSXVOProto_), so the lookup
//     finds nothing, the check comes back NO, and mplayer quietly drops the
//     proxy and renders nowhere -- playback runs to completion with no window
//     ever appearing.
//
//  2. Every scalar argument in mplayer's declaration is qualified `bycopy`,
//     and clang encodes that qualifier into the method type
//     ("i32@0:8Oi16Oi20Oi24Oi28" -- note the `O`s). NSConnection compares the
//     incoming invocation's signature with the server object's method
//     signature exactly, and Swift has no `bycopy`, so a Swift @objc
//     implementation is rejected on arrival:
//     "Object does not implement or has different method signature for
//     selector 'startWithWidth:withHeight:withBytes:withAspect:'".
//
// So the selectors live here in ObjC, spelled exactly as mplayer spells them,
// and forward straight into the vo*-prefixed methods on CoreController.swift,
// which still owns all of the state (shared-memory mapping, display delegate).

#import <Cocoa/Cocoa.h>
#import "MPlayerX-Swift.h"

// the Distant Protocol from mplayer binary
@protocol MPlayerOSXVOProto
-(int) startWithWidth:(bycopy NSUInteger)width withHeight:(bycopy NSUInteger)height withPixelFormat:(bycopy OSType)pixelFormat withAspect:(bycopy float)aspect;
-(void) stop;
-(void) render:(bycopy NSUInteger)frameNum;
-(void) toggleFullscreen;
-(void) ontop;
// Upstream mplayer's vo_corevideo speaks a slightly different dialect of this
// protocol than the patched build MPlayerX used to ship: it reports bytes per
// pixel rather than a pixel format, gives the aspect as an integer scaled by
// 100, renders a single shared buffer rather than two, and takes no frame
// number. Both spellings are declared so either binary can drive MPlayerX.
-(int) startWithWidth:(bycopy int)width withHeight:(bycopy int)height withBytes:(bycopy int)bytes withAspect:(bycopy int)aspect;
-(void) render;
@end

@interface CoreController (MPlayerOSXVOProto) <MPlayerOSXVOProto>
@end

@implementation CoreController (MPlayerOSXVOProto)

//////////////////////////////////////////////Hack to get communicate with mplayer/////////////////////////////////////////////
-(BOOL) conformsToProtocol:(Protocol *)aProtocol
{
	if (aProtocol == @protocol(MPlayerOSXVOProto)) {
		return YES;
	}
	return [super conformsToProtocol: aProtocol];
}

//////////////////////////////////////////////protocol for render/////////////////////////////////////////////////////
-(int) startWithWidth:(bycopy NSUInteger)width withHeight:(bycopy NSUInteger)height withPixelFormat:(bycopy OSType)pixelFormat withAspect:(bycopy float)aspect
{
	return [self voStartWithWidth:width height:height pixelFormat:pixelFormat aspect:aspect];
}

-(int) startWithWidth:(bycopy int)width withHeight:(bycopy int)height withBytes:(bycopy int)bytes withAspect:(bycopy int)aspect
{
	return [self voStartWithWidth:width height:height bytes:bytes aspect:aspect];
}

-(void) stop { [self voStop]; }

-(void) render:(bycopy NSUInteger)frameNum { [self voRender:frameNum]; }

-(void) render
{
	// Upstream mplayer renders a single shared buffer and sends no frame number.
	[self voRender:0];
}

- (void) toggleFullscreen {/* This function should be realized at up-level */}
- (void) ontop {/* This function should be realized at up-level */ }

@end
