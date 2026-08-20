/*
 * MPlayerX - MPXExceptionTrap.h
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

#import <Foundation/Foundation.h>

/**
 * Runs \c body, and if it throws an NSException, hands the exception to
 * \c handler instead of letting it unwind.
 *
 * Swift has no way to catch an NSException, so any Swift code that has to
 * survive one thrown from inside a framework (AppKit text drawing being the
 * case this exists for) routes through this trampoline. Only use it where
 * the ObjC original already had a \@try/\@catch -- it is not a licence to
 * swallow exceptions generally.
 */
void MPXCatchingNSException(void (NS_NOESCAPE ^ _Nonnull body)(void),
							void (NS_NOESCAPE ^ _Nullable handler)(NSException * _Nonnull exception));
