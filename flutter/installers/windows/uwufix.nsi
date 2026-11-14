; uwuFix's Windows installer, uwufix-<version>-setup.exe (docs/flutter-desktop-app-spec.md §10):
;
; - per user, no administrator needed, asking where to install (default
;   %LOCALAPPDATA%\Programs\uwuFix, or wherever an earlier install went);
; - x64 and Arm64 in one installer, picking the computer's own;
; - closes a running copy first, clears the folder, installs, and writes "Uninstall uwuFix.exe"
;   beside the app (the updater tells this install apart by it, lib/desktop/updater.dart);
; - Start menu and desktop shortcuts, and the uwu:// scheme (the app registers it again at every
;   start, links_desktop.dart);
; - /S installs silently, as the app's updater runs it, with --updated and --force-run to start
;   the app afterwards.
;
; Built by .github/workflows/build-desktop.yml:
;   makensis /DVERSION=1.1.0 /DX64=<x64 Release folder> [/DARM64=<arm64 Release folder>] /DOUT=<file> uwufix.nsi

Unicode true
ManifestDPIAware true
RequestExecutionLevel user
SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "x64.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef OUT
  !define OUT "uwufix-${VERSION}-setup.exe"
!endif

!define APP "uwuFix"
!define APPID "org.uwuapps.fixup"
!define EXE "uwuFix.exe"
!define UNINST "Uninstall uwuFix.exe"
!define REGKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPID}"
!define LOCKEY "Software\UwU Apps\uwuFix"

Name "${APP}"
OutFile "${OUT}"
InstallDir "$LOCALAPPDATA\Programs\${APP}"
InstallDirRegKey HKCU "${LOCKEY}" "InstallLocation"
BrandingText "${APP} ${VERSION}"
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${APP} installer"
VIAddVersionKey "CompanyName" "UwU Apps"
VIAddVersionKey "LegalCopyright" "Augy, UwU Apps. MIT licence."

!define MUI_ICON "..\..\windows\runner\resources\app_icon.ico"
!define MUI_UNICON "..\..\windows\runner\resources\app_icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Open ${APP}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Var ForceRun

Function .onInit
  ; The updater's arguments, as an Electron updater passes them.
  ${GetParameters} $0
  ${GetOptions} $0 "--force-run" $1
  ${IfNot} ${Errors}
    StrCpy $ForceRun "1"
  ${EndIf}
FunctionEnd

; A running copy is closed first, or its files can't be replaced.
!macro CloseRunning
  nsExec::Exec 'taskkill /IM "${EXE}" /F'
  Sleep 800
!macroend

Section "Install"
  !insertmacro CloseRunning
  ; Whatever was here before goes, so nothing of an older build is left behind.
  RMDir /r "$INSTDIR"
  SetOutPath "$INSTDIR"
!ifdef ARM64
  ${If} ${IsNativeARM64}
    File /r "${ARM64}\*.*"
  ${Else}
    File /r "${X64}\*.*"
  ${EndIf}
!else
  File /r "${X64}\*.*"
!endif

  WriteUninstaller "$INSTDIR\${UNINST}"

  CreateShortCut "$SMPROGRAMS\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\${EXE}" 0
  ${IfNot} ${Silent}
    CreateShortCut "$DESKTOP\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\${EXE}" 0
  ${EndIf}

  ; uwu://fix links.
  WriteRegStr HKCU "Software\Classes\uwu" "" "URL:uwu"
  WriteRegStr HKCU "Software\Classes\uwu" "URL Protocol" ""
  WriteRegStr HKCU "Software\Classes\uwu\shell\open\command" "" '"$INSTDIR\${EXE}" "%1"'

  WriteRegStr HKCU "${LOCKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${REGKEY}" "DisplayName" "${APP}"
  WriteRegStr HKCU "${REGKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${REGKEY}" "Publisher" "UwU Apps"
  WriteRegStr HKCU "${REGKEY}" "DisplayIcon" "$INSTDIR\${EXE}"
  WriteRegStr HKCU "${REGKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${REGKEY}" "UninstallString" '"$INSTDIR\${UNINST}"'
  WriteRegStr HKCU "${REGKEY}" "QuietUninstallString" '"$INSTDIR\${UNINST}" /S'
  WriteRegStr HKCU "${REGKEY}" "URLInfoAbout" "https://fixup.uwuapps.org"
  WriteRegDWORD HKCU "${REGKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${REGKEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKCU "${REGKEY}" "EstimatedSize" $0

  ; Silent, from the app's updater: open the new version straight away.
  ${If} ${Silent}
  ${AndIf} $ForceRun == "1"
    Exec '"$INSTDIR\${EXE}"'
  ${EndIf}
SectionEnd

Section "Uninstall"
  !insertmacro CloseRunning
  Delete "$SMPROGRAMS\${APP}.lnk"
  Delete "$DESKTOP\${APP}.lnk"
  ReadRegStr $0 HKCU "Software\Classes\uwu\shell\open\command" ""
  ${If} $0 == '"$INSTDIR\${EXE}" "%1"'
    DeleteRegKey HKCU "Software\Classes\uwu"
  ${EndIf}
  ; The app's start at sign-in (launch_at_startup's Run value).
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "${APP}"
  DeleteRegKey HKCU "${REGKEY}"
  DeleteRegKey HKCU "${LOCKEY}"
  RMDir /r "$INSTDIR"
SectionEnd
