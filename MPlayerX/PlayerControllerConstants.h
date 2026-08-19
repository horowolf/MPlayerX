/*
 * MPlayerX - PlayerControllerConstants.h
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

// Split out of PlayerController.h when PlayerController itself moved to
// Swift (PlayerController.swift): Swift can't re-expose top-level constants
// as bare extern identifiers, and RootLayerView.m / ControlUIView.m (still
// Objective-C) reference all of these as bare identifiers. PlayerController.swift
// picks these same symbols up via the bridging header, so both sides keep
// posting/observing under the exact same NSString identity.

extern NSString * const kMPCPlayOpenedNotification;
extern NSString * const kMPCPlayOpenedURLKey;
extern NSString * const kMPCPlayLastStoppedTimeKey;
//-----------------------------------------------------------------
extern NSString * const kMPCPlayStartedNotification;
extern NSString * const kMPCPlayStartedAudioOnlyKey;
//-----------------------------------------------------------------
extern NSString * const kMPCPlayWillStopNotification;
extern NSString * const kMPCPlayStoppedNotification;
extern NSString * const kMPCPlayFinalizedNotification;
//-----------------------------------------------------------------
extern NSString * const kMPCPlayInfoUpdatedNotification;
extern NSString * const kMPCPlayInfoUpdatedKeyPathKey;
extern NSString * const kMPCPlayInfoUpdatedChangeDictKey;
