[colors]
foreground={{ foreground_strip }}
background={{ background_strip }}
selection-foreground={{ selection_foreground_strip }}
selection-background={{ selection_background_strip }}

regular0={{ background_strip }}
regular1={{ red_strip }}
regular2={{ green_strip }}
regular3={{ yellow_strip }}
regular4={{ blue_strip }}
regular5={{ purple_strip }}
regular6={{ cyan_strip }}
regular7={{ foreground_strip }}

bright0={{ muted_strip }}
bright1={{ bright_red_strip }}
bright2={{ bright_green_strip }}
bright3={{ bright_yellow_strip }}
bright4={{ bright_blue_strip }}
bright5={{ bright_magenta_strip }}
bright6={{ bright_cyan_strip }}
bright7={{ bright_foreground_strip }}

# No themed cursor color. foot moved the option between versions and errors on
# the one it does not know: foot 1.13 (archlinux32) rejects `cursor=` inside
# [colors], foot 1.27 (Arch x86_64) rejects `color=` inside [cursor]. One
# static template cannot satisfy both, and an unknown option is a hard config
# error, so neither form is emitted. The cursor falls back to the regular
# foreground and background, reversed.
