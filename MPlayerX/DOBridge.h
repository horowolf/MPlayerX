/*
 * MPlayerX - DOBridge.h
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

#import <Cocoa/Cocoa.h>

// CoreController.swift's rendering thread needs two C APIs that Swift can't
// call directly: NSConnection is annotated NS_SWIFT_UNAVAILABLE (Apple wants
// XPC used instead, but the patched mplayer binary this app talks to over
// Distributed Objects can't be changed), and shm_open() is a variadic C
// function, which Swift refuses to import at all. Both restrictions are
// Swift-compiler-level only -- the underlying ObjC/C APIs work exactly as
// before -- so these thin non-variadic wrappers, written in ObjC, are the
// bridge back to them.

/** Wraps +[NSConnection serviceConnectionWithName:rootObject:], which Swift can't call directly. */
NSObject * _Nullable MPXStartServiceConnection(NSString * _Nonnull name, id _Nonnull rootObject);

/** Wraps shm_open(name, O_RDONLY, S_IRUSR); Swift can't call shm_open directly since it's variadic. */
int MPXShmOpenReadOnly(const char * _Nonnull name);
