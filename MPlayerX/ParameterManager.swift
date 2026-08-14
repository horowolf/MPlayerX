/*
 * MPlayerX - ParameterManager.swift
 */

import Cocoa

private let kPMDefaultAudioOutput = "coreaudio"
private let kPMDefaultVideoOutput = "corevideo"
private let kPMDefaultSubLang = "en,eng,ch,chs,cht,ja,jpn"
private let kPMParMsgLevel = "-msglevel"
private let kPMValMsgLevel = "all=-1:global=4:cplayer=4:identify=4"
private let kPMParSlave = "-slave"
private let kPMParFrameDrop = "-framedrop"
private let kPMParForceIdx = "-forceidx"
private let kPMParNoDouble = "-nodouble"
private let kPMParCache = "-cache"
private let kPMParIPV6 = "-prefer-ipv6"
private let kPMParIPV4 = "-prefer-ipv4"
private let kPMParOsdLevel = "-osdlevel"
private let kPMParSubFuzziness = "-sub-fuzziness"
private let kPMParFont = "-font"
private let kPMParAudioOut = "-ao"
private let kPMParVideoOut = "-vo"
private let kPMParSLang = "-slang"
private let kPMParStartTime = "-ss"
private let kPMParVolume = "-volume"
private let kPMParSubPos = "-subpos"
private let kPMParOSDScale = "-subfont-osd-scale"
private let kPMParTextScale = "-subfont-text-scale"
private let kPMBlank = ""
private let kPMParSubFont = "-subfont"
private let kPMParSubCP = "-subcp"
private let kPMParSubFontAutoScale = "-subfont-autoscale"
private let kPMVal1 = "1"
private let kPMVal2 = "2"
private let kPMParEmbeddedFonts = "-embeddedfonts"
private let kPMParNoEmbeddedFonts = "-noembeddedfonts"
private let kPMParLavdopts = "-lavdopts"
private let kPMParAss = "-ass"
private let kPMParAssColor = "-ass-color"
private let kPMParAssFontScale = "-ass-font-scale"
private let kPMParAssBorderColor = "-ass-border-color"
private let kPMParAssForcrStyle = "-ass-force-style"
private let kPMParAssUsesMargin = "-ass-use-margins"
private let kPMParAssBottomMargin = "-ass-bottom-margin"
private let kPMParAssTopMargin = "-ass-top-margin"
private let kPMParNoAutoSub = "-noautosub"
private let kPMParSub = "-sub"
private let kPMComma = ","
private let kPMParVobSub = "-vobsub"
private let kPMParAC = "-ac"
private let kPMParHWDTS = "hwdts,"
private let kPMParHWAC3 = "hwac3,a52,"
private let kPMParSTPause = "-stpause"
private let kPMParDemuxer = "-demuxer"
private let kPMParOverlapSub = "-overlapsub"
private let kPMParRtspOverHttp = "-rtsp-stream-over-http"
private let kPMParMsgCharset = "-msgcharset"
private let kPMValMsgCharset = "noconv"
private let kPMParChannels = "-channels"
private let kPMParAf = "-af"
private let kPMValScaletempo = "scaletempo"
private let kPMSubParEqualizer = "equalizer="
private let kPMParVf = "-vf"
private let kPMParFieldDominance = "-field-dominance"
private let kPMSubParValYadif = "yadif=1"
private let kPMSubParValMcDet = "mcdeint=2:1:5"
private let kPMSubParPPFD = "fd"
private let kPMSubParPPL5 = "l5"
private let kPMSubParImgEnhNorm = "hb:a/vb:a/dr:a"
private let kPMSubParImgEnhAdv = "ha:a/va:a/dr:a"
private let kPMSubParPPFilter = "pp="
private let kPMSlash = "/"
private let kPMParSubID = "-subid"
private let kPMParNoSub = "-nosub"
private let kPMParDVDProto = "dvd://"
private let kPMParDVDDevice = "-dvd-device"
private let kPMParNoDispCacheLog = "-nodispclog"
private let kPMParEdl = "-edl"
private let kPMParAudioFile = "-audiofile"
private let kSubScaleNoAss: Float = 8.0
private let kPMSubBorderWidthMax: UInt32 = 4

@objc(ParameterManager)
class ParameterManager: NSObject {
    private var paramArray = NSMutableArray(capacity: 80)
    private var font: String?
    private var ao: String? = kPMDefaultAudioOutput
    private var vo: String? = kPMDefaultVideoOutput
    private var subPreferedLanguage: String? = kPMDefaultSubLang
    private var frontColor: UInt32 = 0xFFFFFF00
    private var borderColor: UInt32 = 0x0000000F
    private var assEnabled = true
    private var frameDrop = false
    private var osdLevel: UInt8 = 0

    @objc var subNameRule: SUBFILE_NAMERULE = kSubFileNameRuleContain
    @objc var mplayerArch: String = kX86_64Key
    @objc var supportedOptions: NSSet?
    @objc var guessSubCP = true
    @objc var startTime: Float = -1
    @objc var volume: Float = 100
    @objc var subPos: Float = 100
    @objc var subAlign: UInt32 = UInt32(kPMSubAlignDefault)
    @objc var subScale: Float = 1.5
    @objc var subFont: String?
    @objc var subCP: String?
    @objc var threads: UInt32 = 1
    @objc var textSubs: [Any]?
    @objc var vobSub: String?
    @objc var forceIndex = false
    @objc var dtsPass = false
    @objc var ac3Pass = false
    @objc var useEmbeddedFonts = false
    @objc var cache: UInt32 = 1000
    @objc var preferIPV6 = false
    @objc var letterBoxMode: UInt32 = UInt32(kPMLetterBoxModeNotDisplay)
    @objc var letterBoxHeight: Float = 0.1
    @objc var pauseAtStart = false
    @objc var overlapSub = false
    @objc var rtspOverHttp = false
    @objc var mixToStereo: UInt32 = UInt32(kPMMixDTS5_1ToStereo)
    @objc var demuxer: String?
    @objc var deinterlace: UInt32 = UInt32(kPMDeInterlaceNone)
    @objc var imgEnhance: UInt32 = UInt32(kPMImgEnhanceNone)
    @objc var extraOptions: String?
    @objc var equalizer: [Any]?
    @objc var subBorderWidth: UInt32 = UInt32(kPMSubBorderWidthDefault)
    @objc var noDispSub = false
    @objc var playDisk: Int = Int(kPMPlayDiskNone)
    @objc var assSubMarginV: Int = Int(kPMAssSubMarginVDefault)
    @objc var displayCacheLog = true
    @objc var edlPath: String?
    @objc var audioFilePath: String?

    @objc(setSubFontColor:)
    func setSubFontColor(_ color: NSColor?) {
        guard let color = color else { return }
        frontColor = color.hexValue()
    }

    @objc(setSubFontBorderColor:)
    func setSubFontBorderColor(_ color: NSColor?) {
        guard let color = color else { return }
        borderColor = color.hexValue()
    }

    @objc(supportsStartPausedOption)
    func supportsStartPausedOption() -> Bool {
        return supportsOption(kPMParSTPause)
    }

    @objc func reset() {
        vobSub = nil
        textSubs = nil
        edlPath = nil
        audioFilePath = nil
    }

    private func supportsOption(_ option: String) -> Bool {
        guard let supportedOptions = supportedOptions else { return true }
        let name = option.hasPrefix("-") ? String(option.dropFirst()) : option
        if supportedOptions.contains(name) { return true }
        if name.hasPrefix("no") && supportedOptions.contains(String(name.dropFirst(2))) { return true }
        return false
    }

    private func realVolume(_ value: Float) -> Float {
        return 0.01 * value * value
    }

    private func shouldUsePPFilters(_ value: UInt32) -> Bool {
        return (value & 0xC0) != 0
    }

    @objc(arrayOfParametersWithName:)
    func arrayOfParameters(withName name: String?) -> [Any] {
        var useVideoFilters = false
        var usePPFilters = false
        paramArray.removeAllObjects()

        if let demuxer = demuxer {
            paramArray.add(kPMParDemuxer)
            paramArray.add(demuxer)
        }

        paramArray.add(kPMParMsgLevel)
        paramArray.add(kPMValMsgLevel)
        paramArray.add(kPMParMsgCharset)
        paramArray.add(kPMValMsgCharset)
        paramArray.add(kPMParSlave)

        if frameDrop { paramArray.add(kPMParFrameDrop) }
        if forceIndex { paramArray.add(kPMParForceIdx) }

        paramArray.add(kPMParNoDouble)

        if cache > 0 {
            paramArray.add(kPMParCache)
            paramArray.add(String(format: "%d", cache))
        }

        paramArray.add(preferIPV6 ? kPMParIPV6 : kPMParIPV4)

        if rtspOverHttp && supportsOption(kPMParRtspOverHttp) {
            paramArray.add(kPMParRtspOverHttp)
        }

        paramArray.add(kPMParOsdLevel)
        paramArray.add(String(format: "%d", osdLevel))
        paramArray.add(kPMParSubFuzziness)
        paramArray.add(String(format: "%d", subNameRule.rawValue))

        if let font = font {
            paramArray.add(kPMParFont)
            paramArray.add(font)
        }

        if let ao = ao {
            paramArray.add(kPMParAudioOut)
            paramArray.add(ao)
        }

        if let vo = vo {
            paramArray.add(kPMParVideoOut)
            if vo == kPMDefaultVideoOutput, let name = name {
                paramArray.add(String(format: "%@:shared_buffer:buffer_name=%@", vo, name))
            } else {
                paramArray.add(vo)
            }
        }

        if let subPreferedLanguage = subPreferedLanguage {
            paramArray.add(kPMParSLang)
            paramArray.add(String(format: "%@", subPreferedLanguage))
        }

        if startTime > 0 {
            paramArray.add(kPMParStartTime)
            paramArray.add(String(format: "%.1f", startTime))
        }

        paramArray.add(kPMParSubPos)
        paramArray.add(String(format: "%d", UInt32(subPos)))
        paramArray.add(kPMParOSDScale)
        paramArray.add(String(format: "%.1f", kSubScaleNoAss))
        paramArray.add(kPMParTextScale)
        paramArray.add(String(format: "%.1f", kSubScaleNoAss))

        if let subFont = subFont, subFont != kPMBlank {
            paramArray.add(kPMParSubFont)
            paramArray.add(subFont)
        }

        if let subCP = subCP, subCP != kPMBlank {
            paramArray.add(kPMParSubCP)
            paramArray.add(subCP)
        }

        paramArray.add(kPMParSubFontAutoScale)
        paramArray.add(kPMVal1)
        paramArray.add(useEmbeddedFonts ? kPMParEmbeddedFonts : kPMParNoEmbeddedFonts)

        if overlapSub { paramArray.add(kPMParOverlapSub) }

        if threads > 1 {
            paramArray.add(kPMParLavdopts)
            paramArray.add(String(format: "threads=%d", threads))
        }

        if assEnabled {
            paramArray.add(kPMParAss)
            paramArray.add(kPMParAssColor)
            paramArray.add(String(format: "%X", frontColor))
            paramArray.add(kPMParAssFontScale)
            paramArray.add(String(format: "%.1f", subScale))
            paramArray.add(kPMParAssBorderColor)
            paramArray.add(String(format: "%X", borderColor))

            subBorderWidth = min(kPMSubBorderWidthMax, subBorderWidth)
            var otherStyles = String(format: "Default.BorderStyle=1,Default.MarginV=%d,Default.Outline=%d", assSubMarginV, subBorderWidth)
            if subAlign != UInt32(kPMSubAlignDefault) {
                otherStyles += String(format: ",Default.Alignment=%d", subAlign)
            }

            paramArray.add(kPMParAssForcrStyle)
            paramArray.add(otherStyles)

            if letterBoxMode != UInt32(kPMLetterBoxModeNotDisplay) {
                paramArray.add(kPMParAssUsesMargin)
                if letterBoxMode == UInt32(kPMLetterBoxModeBoth) || letterBoxMode == UInt32(kPMLetterBoxModeBottomOnly) {
                    paramArray.add(kPMParAssBottomMargin)
                    paramArray.add(String(format: "%.2f", letterBoxHeight))
                }
                if letterBoxMode == UInt32(kPMLetterBoxModeBoth) || letterBoxMode == UInt32(kPMLetterBoxModeTopOnly) {
                    paramArray.add(kPMParAssTopMargin)
                    paramArray.add(String(format: "%.2f", letterBoxHeight))
                }
            }
        }

        if guessSubCP { paramArray.add(kPMParNoAutoSub) }

        if let textSubs = textSubs, !textSubs.isEmpty {
            paramArray.add(kPMParSub)
            paramArray.add((textSubs as NSArray).componentsJoined(by: kPMComma))
        }

        if let vobSub = vobSub, vobSub != kPMBlank {
            paramArray.add(kPMParVobSub)
            paramArray.add((vobSub as NSString).deletingPathExtension)
        }

        if dtsPass || ac3Pass {
            paramArray.add(kPMParAC)
            var passString = kPMBlank
            if dtsPass { passString += kPMParHWDTS }
            if ac3Pass { passString += kPMParHWAC3 }
            paramArray.add(passString)
        } else {
            paramArray.add(kPMParVolume)
            paramArray.add(String(format: "%.1f", realVolume(volume)))
            if mixToStereo == UInt32(kPMMixDTS5_1ToStereo) {
                paramArray.add(kPMParChannels)
                paramArray.add(kPMVal2)
            }
        }

        if pauseAtStart && supportsOption(kPMParSTPause) {
            paramArray.add(kPMParSTPause)
        }

        if noDispSub {
            if supportsOption(kPMParSubID) {
                paramArray.add(kPMParSubID)
                paramArray.add("-1")
            } else {
                paramArray.add(kPMParNoSub)
            }
        }

        paramArray.add(kPMParAf)
        var afSettings = [kPMValScaletempo]
        if let equalizer = equalizer, !equalizer.isEmpty {
            let values = equalizer.map { String(format: "%.2f", ($0 as AnyObject).floatValue) }.joined(separator: ":")
            afSettings.append(kPMSubParEqualizer + values)
        }
        paramArray.add(afSettings.joined(separator: ","))

        if shouldUsePPFilters(imgEnhance) {
            useVideoFilters = true
            usePPFilters = true
        }

        if shouldUsePPFilters(deinterlace) {
            useVideoFilters = true
            usePPFilters = true
        } else if deinterlace == UInt32(kPMDeInterlaceYaMc) {
            useVideoFilters = true
            paramArray.add(kPMParFieldDominance)
            paramArray.add(kPMVal1)
        }

        if useVideoFilters {
            var vfSettings = [String]()
            if deinterlace == UInt32(kPMDeInterlaceYaMc) {
                vfSettings.append(kPMSubParValYadif)
                vfSettings.append(kPMSubParValMcDet)
            }

            if usePPFilters {
                var ppSettings = [String]()
                if deinterlace == UInt32(kPMDeInterlaceFFMpeg) {
                    ppSettings.append(kPMSubParPPFD)
                } else if deinterlace == UInt32(kPMDeInterlaceLPF5) {
                    ppSettings.append(kPMSubParPPL5)
                }

                if imgEnhance == UInt32(kPMImgEnhanceNormal) {
                    ppSettings.append(kPMSubParImgEnhNorm)
                } else if imgEnhance == UInt32(kPMImgEnhanceAdvanced) {
                    ppSettings.append(kPMSubParImgEnhAdv)
                }

                vfSettings.append(kPMSubParPPFilter + ppSettings.joined(separator: kPMSlash))
            }

            paramArray.add(kPMParVf)
            paramArray.add(vfSettings.joined(separator: kPMComma))
        }

        if !displayCacheLog && supportsOption(kPMParNoDispCacheLog) {
            paramArray.add(kPMParNoDispCacheLog)
        }

        if let edlPath = edlPath {
            paramArray.add(kPMParEdl)
            paramArray.add(edlPath)
        }

        if let audioFilePath = audioFilePath {
            paramArray.add(kPMParAudioFile)
            paramArray.add(audioFilePath)
        }

        if let extraOptions = extraOptions {
            for option in extraOptions.components(separatedBy: " ") where !option.isEmpty {
                paramArray.add(option)
            }
        }

        if playDisk == Int(kPMPlayDiskDVD) {
            paramArray.insert(kPMParDVDProto, at: 0)
            paramArray.add(kPMParDVDDevice)
        }

        return paramArray as! [Any]
    }
}
