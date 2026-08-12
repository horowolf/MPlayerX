/*
 * MPlayerX - MPXLegacyAccessibility.h
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

// Declaration-only category (no @implementation -- these selectors are
// already implemented dynamically by AppKit at the Objective-C runtime
// level on NSObject/NSResponder/NSCell). The pre-10.10 string-keyed
// accessibility informal protocol isn't part of AppKit's modern Swift
// overlay, so a Swift subclass can't "override" these the normal way. This
// category makes them visible to Swift as regular NSObject methods (via the
// bridging header) so PlayerWindow.swift / MPXWindowButton.swift can
// override them and call super the usual way, matching the original
// Objective-C implementations exactly.

#import <Cocoa/Cocoa.h>

@interface NSObject (MPXLegacyAccessibility)

-(NSArray<NSString*>*) accessibilityAttributeNames;
-(id) accessibilityAttributeValue:(NSString*)attribute;
-(BOOL) accessibilityIsAttributeSettable:(NSString*)attribute;
-(void) accessibilitySetValue:(id)value forAttribute:(NSString*)attribute;
-(BOOL) accessibilityIsIgnored;
-(void) accessibilityPerformAction:(NSString*)action;

@end
