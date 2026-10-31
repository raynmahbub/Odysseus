NAME := Odysseus
SCHEME := Feather
PLATFORMS := iphoneos maccatalyst

TMP := $(TMPDIR)/$(NAME)

.PHONY: all clean $(PLATFORMS) verify-ipa

all: $(PLATFORMS)

clean:
	rm -rf $(TMP)
	rm -rf packages
	rm -rf Payload
	rm -rf _build
	rm -rf deps cert.json

$(PLATFORMS):
	rm -rf _build

	@if [ "$@" = "iphoneos" ]; then \
		DEST="generic/platform=iOS"; \
	else \
		DEST="generic/platform=macOS,variant=Mac Catalyst"; \
	fi; \
	xcodebuild \
		-project Feather.xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination "$$DEST" \
		-derivedDataPath $(TMP)/$@ \
		-skipPackagePluginValidation \
		CODE_SIGNING_ALLOWED=NO \
		ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=NO

	mkdir -p _build/Payload
	cp -R _build/Applications/*.app _build/Payload/$(NAME).app
	chmod -R 0755 _build/Payload/$(NAME).app
	codesign --force --deep --sign - --timestamp=none _build/Payload/$(NAME).app

	mkdir -p packages

	@if [ "$@" = "iphoneos" ]; then \
		ditto -c -k --sequesterRsrc --keepParent _build/Payload "packages/$(NAME).ipa"; \
	else \
		ditto -c -k --sequesterRsrc --keepParent _build/Payload/$(NAME).app "packages/$(NAME)_Catalyst.zip"; \
	fi

verify-ipa:
	scripts/verify_ipa.sh packages/$(NAME).ipa
