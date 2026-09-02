#!/bin/bash
source "$(dirname "$0")/base-test.sh"

# Qt Quick's software scenegraph has no shader stage, so a MultiEffect draws
# nothing and reports nothing. On this fork the session always runs with
# QT_QUICK_BACKEND=software, which blanked every thumbnail in the image
# picker's carousel: the tile borders drew, the images inside them did not.
# Guard the two halves of the fix so a later merge cannot quietly undo it.

run_node_test <<'JS'
const fs = require('fs')

const launcher = fs.readFileSync(path.join(root, 'bin/omarchy-hyprland-launch'), 'utf8')
const picker = fs.readFileSync(path.join(root, 'shell/plugins/image-picker/ImagePicker.qml'), 'utf8')

assert(
  /^export QT_QUICK_BACKEND=software$/m.test(launcher),
  'the session launcher still selects the software scenegraph the guard tests for'
)

assert(
  /readonly property bool shaderEffectsAvailable: Quickshell\.env\("QT_QUICK_BACKEND"\) !== "software"/.test(picker),
  'image picker derives shader availability from the backend the launcher selects'
)

assert(
  /layer\.enabled: root\.shaderEffectsAvailable/.test(picker),
  'image picker carousel tiles skip the masking layer on the software backend'
)

assert(
  !/layer\.enabled: true\s*\n\s*layer\.smooth: true\s*\n\s*layer\.effect: MultiEffect/.test(picker),
  'image picker never enables a MultiEffect layer unconditionally'
)
JS
