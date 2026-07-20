# MacPass

> **This is a maintained fork of [MacPass](https://github.com/MacPass/MacPass).**
> The original project has seen little activity, so this fork keeps MacPass building and running on modern macOS and Xcode, and ships signed and notarized releases. All credit for MacPass itself goes to Michael Starke and the [original contributors](https://github.com/MacPass/MacPass/graphs/contributors).

There are a lot of iOS KeePass tools around but a distinct lack of a good native macOS version.
KeePass can be used via Mono on macOS but lacks vital functionality and feels sluggish and simply out of place.

MacPass is an attempt to create a native macOS port of KeePass on a solid open source foundation with a vibrant community pushing it further to become the best KeePass client for macOS.

## What's different in this fork

- Builds with current Xcode on Apple silicon (works around Carthage and TransformerKit incompatibilities)
- Releases are universal binaries (Apple silicon + Intel), code signed, notarized, and shipped as DMG with SLSA build provenance attestations
- Automatic updates via Sparkle, served from this fork's own appcast
- Bundled [MacPassHTTP](https://github.com/orestesgaolin/MacPassHTTP) plugin support
- Assorted fixes and features (e.g. option to hide the Dock icon, selecting a downloaded favicon as the entry icon)

## Download

Pre-built, signed and notarized DMGs are published on the [Releases page](https://github.com/orestesgaolin/MacPass/releases).

Releases are built by GitHub Actions and include [SLSA build provenance attestations](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds). You can verify a downloaded DMG with:

```bash
gh attestation verify MacPass-<version>.dmg --owner orestesgaolin
```

Once installed, the app keeps itself up to date via Sparkle.

## How to Contribute

If you want to contribute by fixing a bug, adding a feature or improving localization you're awesome! Open an [issue](https://github.com/orestesgaolin/MacPass/issues) or a [pull request](https://github.com/orestesgaolin/MacPass/pulls) on this fork.

## How to Build

### Prerequisites

- Xcode (the release builds use Xcode on macOS 15)
- [Carthage](https://github.com/Carthage/Carthage#installing-carthage): `brew install carthage`

### 1. Fetch the source

Clone with submodules — the DDHotKey and MacPassHTTP dependencies are git submodules:

```bash
git clone --recursive https://github.com/orestesgaolin/MacPass
cd MacPass
```

### 2. Check out dependencies

Carthage's own build step is broken on Apple silicon with recent Xcode versions, so only resolve and check out the sources without building:

```bash
carthage bootstrap --no-build
```

Then apply the TransformerKit compatibility fix (its `@import` usage breaks on Xcode 15+):

```bash
./scripts/fix_transformerkit.sh
```

### 3. Build the frameworks

Because Carthage can't build them, the dependency frameworks are built manually into `Carthage/Build/Mac`:

```bash
mkdir -p Carthage/Build/Mac

# Sparkle ships as a pre-built binary — download the version pinned in Cartfile.resolved
SPARKLE_VERSION=$(grep -i sparkle Cartfile.resolved | grep -oE '"[0-9][^"]*"' | tail -1 | tr -d '"')
curl -sSL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" -o /tmp/Sparkle.tar.xz
mkdir -p /tmp/Sparkle && tar xf /tmp/Sparkle.tar.xz -C /tmp/Sparkle
cp -R /tmp/Sparkle/Sparkle.framework Carthage/Build/Mac/

# HNHUi
xcodebuild build \
  -project Carthage/Checkouts/HNHUi/HNHUi.xcodeproj \
  -scheme HNHUi -configuration Release \
  ARCHS="arm64 x86_64" SDKROOT=macosx \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  SYMROOT=/tmp/HNHUi-build OBJROOT=/tmp/HNHUi-obj
cp -R /tmp/HNHUi-build/Release/HNHUi.framework Carthage/Build/Mac/

# KissXML
xcodebuild build \
  -project Carthage/Checkouts/KissXML/KissXML.xcodeproj \
  -scheme "KissXML (macOS)" -configuration Release \
  ARCHS="arm64 x86_64" SDKROOT=macosx \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  SYMROOT=/tmp/KissXML-build OBJROOT=/tmp/KissXML-obj
cp -R /tmp/KissXML-build/Release/KissXML.framework Carthage/Build/Mac/

# KeePassKit (expects KissXML in its own Carthage/Build/Mac)
mkdir -p Carthage/Checkouts/KeePassKit/Carthage/Build/Mac
ln -sf "$(pwd)/Carthage/Build/Mac/KissXML.framework" \
  Carthage/Checkouts/KeePassKit/Carthage/Build/Mac/KissXML.framework
xcodebuild build \
  -project Carthage/Checkouts/KeePassKit/KeePassKit.xcodeproj \
  -target "KeePassKit macOS" -configuration Release \
  ARCHS="arm64 x86_64" SDKROOT=macosx \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  SYMROOT=/tmp/KeePassKit-build OBJROOT=/tmp/KeePassKit-obj
cp -R /tmp/KeePassKit-build/Release/KeePassKit.framework Carthage/Build/Mac/

# TransformerKit
xcodebuild build \
  -workspace Carthage/Checkouts/TransformerKit/TransformerKit.xcworkspace \
  -scheme "TransformerKit macOS" -configuration Release \
  -derivedDataPath /tmp/TransformerKit-build \
  ARCHS="arm64 x86_64" SDKROOT=macosx \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
cp -R /tmp/TransformerKit-build/Build/Products/Release/TransformerKit.framework Carthage/Build/Mac/
```

After this, `Carthage/Build/Mac` should contain `KeePassKit`, `HNHUi`, `TransformerKit`, `KissXML`, and `Sparkle` frameworks.

### 4. Build MacPass

Open `MacPass.xcodeproj` in Xcode and run the `MacPass` scheme, or build from the command line:

```bash
xcodebuild build \
  -project MacPass.xcodeproj \
  -scheme MacPass \
  -configuration Release \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

If you run into signing issues take a look at [Issue #92](https://github.com/MacPass/MacPass/issues/92) of the original project. Since Sparkle is disabled only on the CI build and in Debug mode, you have to explicitly disable it in Release (`NO_SPARKLE=NO_SPARKLE`). Otherwise warnings on unsecure updates will appear.

The complete, always up-to-date build recipe — including code signing, notarization, and DMG packaging — is in [`.github/workflows/release.yml`](.github/workflows/release.yml).

## System Requirement

Releases of this fork are universal binaries (Apple silicon and Intel) and require macOS 10.14 Mojave or later.

## What does it look like?

![image](/Assets/Screenshots/Locked.png)

More Screenshots in the original project's [Wiki](https://github.com/MacPass/MacPass/wiki/Screenshots)

## Alternatives

[KeePassX](https://www.keepassx.org) and its fork [KeePassXC](https://github.com/keepassxreboot/keepassxc). Qt based cross plattform port.

[KyPass Companion](http://www.kyuran.be/logiciels/kypass4mac/). Native macOS client.

[KeeWeb](https://keeweb.info). Electron based cross plattform port. Since it's browser based you can pretty much run it anywhere.

## License

MacPass, a KeePass compatible Password Manager for OS X
Copyright (c) 2012-2017 Michael Starke (HicknHack Software GmbH) and all [MacPass contributors](https://github.com/MacPass/MacPass/graphs/contributors)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of

MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.

## App Store

Due to being licensed under GPLv3 it's not possible to publish a version of MacPass on the App Store.
For further details, take a look at the [explanation](https://www.fsf.org/news/2010-05-app-store-compliance) of the Free Software Foundation.

## Contributions

The following list might not be complete, please refer to [merged Pull Requests](https://github.com/MacPass/MacPass/pulls?utf8=✓&q=is%3Apr+is%3Aclosed+is%3Amerged) of the original project on GitHub for more details. Please open an issue if you think someone is missing from this list!

### Art

[Iiro Jäppinen](https://iiro.jappinen.me) MacPass icon

[Thom Williams](https://github.com/thomscode) Document icons

[Joanna Olsen](https://github.com/JoannaOlsen) Database Icons

### Contributors

[ad](mailto:github.mnms@mamber.net),
[Alessandro Vinciguerra](mailto:30745465+Arc676@users.noreply.github.com),
[Alex Borisov](mailto:alex@alexborisov.org),
[Alex Seeholzer](mailto:seeholzer@gmail.com),
[amd](mailto:amd@gurge.com),
[Andrew Schleifer](mailto:me@andrewschleifer.name),
[AntoineCa](mailto:antoine@carrincazeaux.fr),
[Anton Glezman](mailto:anton@glezman.ru),
[Benjamin Steinwender](mailto:b@stbe.at),
[binarious](mailto:bieder.martin@googlemail.com),
[Can Rau](mailto:cansrau@gmail.com),
[Carlos Filipe Simões](mailto:ravemir@users.noreply.github.com),
[Chester Liu](mailto:skyline75489@outlook.com),
[Chhom Seng](mailto:chhom.seng@gmail.com),
[Christoph Leimbrock](mailto:christoph.leimbrock@gmx.de),
[Cory Hutchison](mailto:cjhutchi@users.noreply.github.com),
[César Arratia](mailto:buttcmd@gmail.com),
[Daniele Polencic](mailto:daniele.polencic@gmail.com),
[darnel](mailto:vojta.j@gmail.com),
[Deiwin Sarjas](mailto:deiwin.sarjas@gmail.com),
[Deniz Türkoglu](mailto:denizt@users.noreply.github.com),
[Dennis Bolio](mailto:git@bolio.nl),
[Dylan Smith](mailto:dylansmith@gmail.com),
[eiermaaaan](mailto:37532252+eiermaaaan@users.noreply.github.com),
[Erwann Mest](mailto:m+github@kud.io),
[Filipe Farinha](mailto:filipe@ktorn.com),
[floriangouy](mailto:florian.gouy@gmail.com),
[Francesco Servida](mailto:info@francescoservida.ch),
[Frank Enderle](mailto:frank.enderle@anamica.de),
[Frank Kooij](mailto:FrankKooij@users.noreply.github.com),
[Gaétan Ryckeboer](mailto:gryckeboer@jouve.com),
[Geigi](mailto:git@geigi.de),
[George Snow](mailto:gsnowiii@gmail.com),
[Henri de Jong](mailto:henridejong@gmail.com),
[James Hurst](mailto:jamesrhurst@outlook.com),
[Jannick Hemelhof](mailto:mister.jannick@gmail.com),
[Jefftree](mailto:jeffrey.ying86@live.com),
[Jellyfrog](mailto:Jellyfrog@users.noreply.github.com),
[Jesse Reppin](mailto:mail@jessereppin.de),
[Joanna Olsen](mailto:jo4flash@gmail.com),
[Josh Halstead](mailto:jhalstead85@gmail.com),
[Kurt](mailto:kurt@soapbox-software.com),
[Laurent Cozic](mailto:laurent22@users.noreply.github.com),
[Lenucksi](mailto:lenucksi@users.noreply.github.com),
[Leonardo Faoro](mailto:lfaoro@users.noreply.github.com),
[Liam Anderson](mailto:liam.anderson.91@gmail.com),
[m0yP](mailto:moises@perez.lt),
[Maarten Terpstra](mailto:m.l.terpstra@student.rug.nl),
[Mario Sangiorgio](mailto:mariosangiorgio@gmail.com),
[MBibal](mailto:michel.bibal@gmail.com),
[Michael Belz](mailto:mbelz@outlook.de),
[MichaelKo](mailto:viacheslav.sychov@gmail.com),
[Michal Jaglewicz](mailto:michalj@webii.pl),
[Moises Perez](mailto:moises@perez.lt),
[mrdoggy](mailto:mrdoggy.all@gmail.com),
[Nathan Landis](mailto:nathanlandis@gmail.com),
[Nathaniel Madura](mailto:nmadura@umich.edu),
[neuroine](mailto:d.dzieduch@gmail.com),
[Oleksandr Yakubchyk](mailto:buddax2@gmail.com),
[Patrik Thunström](mailto:magebarf@gmail.com),
[rdoering](mailto:rdoering.info@gmail.com),
[remi6397](mailto:remi6397@gmail.com),
[Roman Verchikov](mailto:roman-verchikov@users.noreply.github.com),
[Ryan Rogers](mailto:ryan@timewasted.me),
[Sitsofe Wheeler](mailto:sitsofe@yahoo.com),
[Stephen Taylor](mailto:schtee.taylor@gmail.com),
[thesoundofom](mailto:45923716+thesoundofom@users.noreply.github.com),
[Thom](mailto:thomscode@gmail.com),
[Thorsten Jacoby](mailto:tjacoby@gmail.com),
[Veit-Hendrik Schlenker](mailto:git@vhschlenker.de),
[Volcyy](mailto:Volcyy@users.noreply.github.com),
[Yonatan Mittlefehldt](mailto:yono@toojuice.com),
[Zero King](mailto:l2dy@icloud.com),
[Zhao Peng](mailto:patchao2000@gmail.com)

## Copyright

This Project is based upon the following work:

[KeePassKit](https://github.com/MacPass/KeePassKit) Copyright 2012 HicknHack Software GmbH. All rights reserved.
[HNHUi](https://github.com/mstarke/HNHUi) Copyright 2012 HicknHack Software GmbH. All rights reserved.
[MiniKeePass](https://github.com/MiniKeePass/MiniKeePass) Copyright 2011 Jason Rush and John Flanagan. All rights reserved.
[KeePass Database Library](https://github.com/mpowrie/KeePassLib) Copyright 2010 Qiang Yu. All rights reserved.
[PXSourceList](https://github.com/Perspx/PXSourceList) Copyright 2011, Alex Rozanski. All rights reserved.
[KSPasswordField](https://github.com/karelia/SecurityInterface) Copyright 2012 Mike Abdullah, Karelia Software. All rights reserved.
[DDHotKey](https://github.com/davedelong/DDHotKey) Copyright [Dave DeLong](http://www.davedelong.com). All rights reserved.
[Sparkle](http://sparkle.andymatuschak.org) Copyright 2006 Andy Matuschak
[TransformerKit](https://github.com/mattt/TransformerKit) Licensed under MIT license. Copyright 2012 [Mattt Thompson](http://mattt.me/). All rights reserved
[MJGFoundation](https://github.com/mstarke/MJGFoundation) Licensed under BSD 2-Clause License. Copyright 2011 [Matt Galloway](http://www.galloway.me.uk/). All rights reserved.
[ShortcutRecorder](http://wafflesoftware.net/shortcut/) Copyright 2006—2013 all [Shortcut Recorder contributors](http://wafflesoftware.net/shortcut/contributors/)
[NSBundle Codesignature Check](http://jedda.me/2012/03/verifying-plugin-bundles-using-code-signing/) Copyright 2014 [Jedda Wignall](http://jedda.me). All rights reserved.

See submodules for additional Licenses
