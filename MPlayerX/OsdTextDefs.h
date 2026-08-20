/*
 * MPlayerX - OsdTextDefs.h
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

// OsdText itself is Swift now, but its owner tag has to keep the exact
// constant names kOSDOwnerTime / kOSDOwnerOther for the ObjC callers that are
// still waiting to be ported (ControlUIView, RootLayerView). A Swift @objc
// enum would rename them, so the plain C enum stays here and both languages
// import it. Fold it into OsdText.swift once those two callers are Swift.

typedef enum
{
	kOSDOwnerTime = 1,
	kOSDOwnerOther = 2
} OSDOWNER;
