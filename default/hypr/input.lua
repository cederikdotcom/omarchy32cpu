-- https://wiki.hypr.land/Configuring/Basics/Variables/#input

local function dmi_product_name()
  local file = io.open("/sys/class/dmi/id/product_name", "r")
  if not file then
    return ""
  end

  local product = file:read("*l") or ""
  file:close()
  return product
end

-- The i686 Hyprland build corrupts its heap when this input block is applied
-- on the first-generation MacBook. The failure is input-driven: the session
-- reaches the desktop, then aborts while handling appletouch or keyboard
-- state. Hyprland's defaults handle both devices correctly, so leave this one
-- model on those defaults while retaining the rest of Omarchy's desktop.
if dmi_product_name() == "MacBook1,1" then
  return
end

local function read_vconsole()
  local values = {}
  local file = io.open("/etc/vconsole.conf", "r")
  if not file then
    return values
  end

  for line in file:lines() do
    local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if key and value then
      value = value:gsub("%s+#.*$", "")
      value = value:gsub('^"(.*)"$', "%1")
      value = value:gsub("^'(.*)'$", "%1")
      values[key] = value
    end
  end

  file:close()
  return values
end

-- Layouts that can't type Latin letters. Keep in sync with the list in
-- etc/mkinitcpio.conf.d/omarchy_hooks.conf.
local non_latin_layouts =
  " af am ara bd bg by et ge gr il in iq ir kg kh kz la lk mk mm mn mv np rs ru sy th tj ua "

local vconsole = read_vconsole()

local kb_layout = vconsole.XKBLAYOUT or "us"
local kb_variant = vconsole.XKBVARIANT or ""
-- CapsLock is the compose key, so Caps Lock itself has to live somewhere else.
-- Both Shifts together is the usual home for it, but it's easy to hit by
-- accident while typing. The _cancel variant sets Caps Lock the same way and
-- releases it on the next lone Shift, so a misfire clears itself.
local kb_options = "compose:caps,shift:both_capslock_cancel"

-- Hyprland resolves keybindings against the first entry in kb_layout, not the
-- layout that's currently active, so Omarchy's Latin-keysym bindings (SUPER + W
-- and friends) only fire when a Latin layout leads. Installing with a non-Latin
-- one would otherwise leave the desktop unusable.
if non_latin_layouts:find(" " .. kb_layout:match("^[^,]*") .. " ", 1, true) then
  kb_layout = "us," .. kb_layout
  kb_variant = "," .. kb_variant
  -- Reach the original layout with Left Alt + Right Alt.
  kb_options = kb_options .. ",grp:alts_toggle"
end

hl.config({
  input = {
    kb_layout = kb_layout,
    kb_variant = kb_variant,
    kb_model = "",
    kb_options = kb_options,
    kb_rules = "",
    follow_mouse = 1,
    sensitivity = 0,

    repeat_rate = 40,
    repeat_delay = 250,

    -- FORK: off, because upstream's `true` takes the compositor down on the
    -- 32-bit target. Turning numlock on at startup makes Hyprland build a
    -- second xkb state for every keyboard it opens, and on i686 that path
    -- corrupts the heap: glibc aborts a few allocations later with
    -- "malloc(): invalid size (unsorted)", usually inside a pixman region
    -- realloc on the DRM page-flip path, start-hyprland restarts the
    -- compositor in safe mode, and the safe-mode dialog then segfaults for
    -- want of hyprland-qtutils. That is the login loop that made the i686
    -- desktop unreachable.
    --
    -- Bisected 2026-09-02 on a fresh i686 install at 2048 MB, one setting per
    -- run, 4 to 12 starts per variant: the whole config died 0/5, this line
    -- alone died 0/4, and the whole config with it off came back 4/5. The
    -- underlying renderer bug is still there and still has to be fixed; this
    -- keeps the session out of the one path that reaches it every time.
    --
    -- The cost is a keyboard that starts with numlock off. The first target
    -- has no numpad.
    numlock_by_default = false,

    touchpad = {
      natural_scroll = false,
      clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },

  misc = {
    key_press_enables_dpms = true,
    mouse_move_enables_dpms = true,
  },
})

-- Scroll nicely in the terminal.
o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })
