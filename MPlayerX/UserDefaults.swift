/*
 * MPlayerX - UserDefaults.h
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

// Was UserDefaults.h/.m. Every key keeps the exact same bare identifier and
// string value it had as an `extern NSString * const`, so both the call sites
// and the on-disk defaults are unchanged.

////////////////////////////UserDefaults defination/////////////////////////////////
let kUDKeyVolume = "volume"
let kUDKeyOnTopMode = "OnTopMode"
let kUDKeyCtrlUIAutoHideTime = "CtrlUIAutoHideTime"
let kUDKeySpeedStep = "SpeedStepIncre"
let kUDKeySeekStepL = "SeekStepTimeL"
let kUDKeySeekStepR = "SeekStepTimeR"
let kUDKeySeekStepU = "SeekStepTimeU"
let kUDKeySeekStepB = "SeekStepTimeB"
let kUDKeyVolumeStep = "VolumeStep"
let kUDKeyAutoPlayNext = "AutoPlayNext"
let kUDKeySubFontPath = "SubFontPath"
let kUDKeySnapshotSavePath = "SnapshotSavePath"
let kUDKeyStartByFullScreen = "StartByFullScreen"
let kUDKeySubDelayStepTime = "SubDelayStepTime"
let kUDKeyAudioDelayStepTime = "AudioDelayStepTime"
let kUDKeyPrefer64bitMPlayer = "Prefer64bitMPlayer"
let kUDKeyEnableMultiThread = "EnableMultiThread"
let kUDKeySubScale = "SubScale"
let kUDKeySubScaleStepValue = "SubScaleStepValue"
let kUDKeySwitchTimeHintPressOnAbusolute = "TimeHintPrsOnAbs"
let kUDKeyTimeTextAltTotal = "TimeTextAltTotal"
let kUDKeyQuitOnClose = "QuitOnClose"
let kUDKeySubFontColor = "SubFontColor"
let kUDKeySubFontBorderColor = "SubFontBorderColor"
let kUDKeyCtrlUIBackGroundAlpha = "CtrlUIBackGroundAlpha"
let kUDKeyForceIndex = "ForceIndex"
let kUDKeySubFileNameRule = "SubFileNameRule"
let kUDKeyDTSPassThrough = "DTSPassThrough"
let kUDKeyAC3PassThrough = "AC3PassThrough"
let kUDKeyShowOSD = "ShowOSD"
let kUDKeyOSDFontSizeMax = "OSDFontSizeMax"
let kUDKeyOSDFontSizeMin = "OSDFontSizeMin"
let kUDKeyOSDFrontColor = "OSDFrontColor"
let kUDKeyOSDAutoHideTime = "OSDAutoHideTime"
let kUDKeyThreadNum = "NumberOfThreads"
let kUDKeyUseEmbeddedFonts = "UseEmbeddedFonts"
let kUDKeyCacheSize = "CacheSize"
let kUDKeyPreferIPV6 = "PreferIPV6"
let kUDKeyCacheSizeLocalMinLimit = "CacheSizeLocalMinLimit"
let kUDKeyCacheSizeLocalTime = "CacheSizeLocalTime"
let kUDKeyFullScreenKeepOther = "FullScreenKeepOther"
let kUDKeyLetterBoxMode = "LetterBoxMode"
let kUDKeyLetterBoxModeAlt = "LetterBoxModeAlt"
let kUDKeyLetterBoxHeight = "LetterBoxHeight"
let kUDKeyVideoTunerStepValue = "VideoTunerStepValue"
let kUDKeyARKeyRepeatTimeInterval = "ARKeyRepeatTimeInterval"
let kUDKeyARKeyRepeatTimeIntervalLong = "ARKeyRepeatTimeIntervalLong"
let kUDKeyPlayWhenOpened = "PlayWhenOpened"
let kUDKeyTextSubtitleCharsetConfidenceThresh = "TextSubCharsetConfidenceThresh"
let kUDKeyTextSubtitleCharsetManual = "TextSubCharsetManual"
let kUDKeyTextSubtitleCharsetFallback = "TextSubCharsetFallback"
let kUDKeyOverlapSub = "OverlapSub"
let kUDKeyRtspOverHttp = "RtspOverHttp"
let kUDKeyFFMpegHandleStream = "FFMpegHandleStream"
let kUDKeyMixToStereoMode = "MixToSterMode"
let kUDKeyAutoResume = "AutoResume"
let kUDKeyHideTitlebar = "HideTitlebar"
let kUDKeyAlwaysHideDockInFullScrn = "AlwaysHideDockInFullScrn"
let kUDKeyLogMode = "LogMode"
let kUDKeyImgEnhanceMethod = "ImgEnhMethod"
let kUDKeyDeIntMethod = "DeIntMethod"
let kUDKeyExtraOptions = "ExtraOptions"
let kUDKeyEQSettings = "EQSettings"
let kUDKeyAutoSaveEQSettings = "ASEQS"
let kUDKeyVTSettings = "VTSettings"
let kUDKeyAutoSaveVTSettings = "ASVTS"
let kUDKeySubAlign = "SubAlign"
let kUDKeySubBorderWidth = "SubBorderWidth"
let kUDKeyDisableHScrollSeek = "DisableHScrollSeek"
let kUDKeyDisableVScrollVol = "DisableVScrollVol"
let kUDKeyLBAutoHeightInFullScrn = "LBAutoHeightInFullScrn"
let kUDKeyNoDispSub = "NoDispSub"
let kUDKeyCloseWndOnEsc = "CloseWndOnEsc"
let kUDKeyPlayWhenEnterFullScrn = "PlayWhenEnterFullScrn"
let kUDKeySupportAppleRemote = "SupportAppleRemote"
let kUDKeyAutoDetectSPDIF = "AutoDetectSPDIF"
let kUDKeyAssSubMarginV = "AssSubMarginV"
let kUDKeyDontResizeWhenContinuousPlay = "DontResizeWhenContinuousPlay"
let kUDKeyResizeControlBar = "ResizeControlBar"
let kUDKeyInitialFrameSizeRatio = "InitialFrameSizeRatio"
let kUDKeyDisableLastStopBookmark = "DisableLastStopBookmark"
let kUDKeyEnableOpenRecentMenu = "EnableOpenRecentMenu"
let kUDKeyOldFullScreenMethod = "OldFullScreenMethod"
let kUDKeyAlwaysUseSecondaryScreen = "AlwaysUseSecondaryScreen"
let kUDKeySelectedPrefView = "SelectedPrefView"
let kUDKeyCloseWindowWhenStopped = "CloseOnStopped"
let kUDKeyResizeStep = "ResizeStep"
let kUDKeyFrameScaleStep = "FrameScaleStep"
let kUDKeyThreeFingersPinchThreshRatio = "TFPThreshRatio"
let kUDKeyFourFingersPinchThreshRatio = "FFPThreshRatio"
let kUDKeyPinPMode = "PinPMode"
