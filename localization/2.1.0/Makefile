
#this one must be ahead of EXPAND since FILES will be defined 
DESTROOT = results

define EXPAND

  FILES := $$(filter-out .git,$$(filter-out .svn, $$(filter-out English.lproj, $$(filter-out $(DESTROOT),$$(wildcard $(1)*)))))

  DIRS := 

  $$(foreach e, $$(FILES), $$(if $$(wildcard $$(e)/*), $$(eval DIRS := $$(DIRS) $$(e))))

  FILES := $$(filter-out $$(DIRS),$$(FILES))

  ALLFILES := $$(ALLFILES) $$(FILES)

  $$(foreach e,$$(DIRS),$$(eval $$(call EXPAND,$$(e)/)))

endef

$(eval $(call EXPAND))

############### Source of the xib and strings #################
XIBS = $(filter %.xib,$(ALLFILES))
STRS = $(filter %.strings,$(ALLFILES))
RTFS = $(filter %.rtf,$(ALLFILES))

### the compiled results of xib
NIBS = $(subst .xib,.nib,$(XIBS))

### There must be at least one strings file in the folder
### So it is safe to define the dir
LANG_DIRS = $(dir $(STRS))

############ the destination of every localization ############
DEST_DIRS = $(addprefix $(DESTROOT)/, $(LANG_DIRS))

TARGET_STRS = $(addprefix $(DESTROOT)/, $(STRS))
TARGET_NIBS = $(addprefix $(DESTROOT)/, $(NIBS))
TARGET_RTFS = $(addprefix $(DESTROOT)/, $(RTFS))

########################## Tragets #############################
# The .lproj sources in this tree are 1.0.x-era xibs in the old
# NSKeyedArchiver format, and their outlets and actions target Objective-C
# classes the Swift rewrite removed. A MainMenu.nib built from one of them
# makes the app exit at launch in every language that ships it: on the same
# binary, -AppleLanguages '(en)' runs and '(zh-Hant)' dies within seconds
# with no crash report, and moving zh_TW.lproj/MainMenu.nib out of the built
# bundle fixes it. Pref/Inspector/Equalizer/VideoTuner/SubEncoding are dead
# weight on top of that -- those dialogs are SwiftUI now and their xibs are
# gone from the project.
#
# So no nib is built or shipped. The strings and Credits.rtf still are, which
# leaves non-English users a working app with English menus and translated
# strings, instead of one that will not start. Put $(TARGET_NIBS) back here
# once the xibs have been regenerated from the current MainMenu.xib.
all: $(TARGET_STRS) $(TARGET_RTFS)

.PHONY:clean
clean:
	rm -Rf $(DESTROOT)

############################# rules ############################
$(DESTROOT)/%.nib: %.xib $(DESTROOT)
#	cp "$<" "$@"
	ibtool --compile "$@" "$<"

$(DESTROOT)/%.strings: %.strings $(DESTROOT)
	cp "$<" "$@"

$(DESTROOT)/%.rtf: %.rtf $(DESTROOT)
	cp "$<" "$@"

$(DESTROOT):
	mkdir -p $(DEST_DIRS)