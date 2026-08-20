/*
 * MPlayerX - DisplayLayerDefs.h
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

// The two aspect-ratio macros that used to live in DisplayLayer.h, kept in a
// header of their own now that DisplayLayer itself is Swift. Only the ObjC
// files that are still waiting to be ported need them (RootLayerView); Swift
// code uses kDisplayAspectRatioInvalid / IsDisplayLayerAspectValid() from
// DisplayLayer.swift instead. Delete this header once RootLayerView is Swift.

// this value must be less than 0; internally it is actually compared against 0
#define kDisplayAscpectRatioInvalid		(-1)

#define IsDisplayLayerAspectValid(x)	(x > 0)
