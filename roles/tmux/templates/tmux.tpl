
## CPU specific config
set -g @cpu_low_icon "ᚋ"
set -g @cpu_medium_icon "ᚌ"
set -g @cpu_high_icon "ᚍ"

set -g @cpu_low_fg_color "#[fg=#00ff00]"
set -g @cpu_medium_fg_color "#[fg=#ffff00]"
set -g @cpu_high_fg_color "#[fg=#ff0000]"

set -g @cpu_low_bg_color "#[bg=#00ff00]"
set -g @cpu_medium_bg_color "#[bg=#ffff00]"
set -g @cpu_high_bg_color "#[bg=#ff0000]"


# Plugins
#########
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-copycat'
set -g @plugin 'tmux-plugins/tmux-resurrect'
#set -g @plugin 'tmux-plugins/tmux-logging'
set -g @plugin 'tmux-plugins/tmux-pain-control'
#set -g @plugin 'tmux-plugins/tmux-cpu'
set -g @plugin 'tmux-plugins/tmux-open'

set -g @plugin 'thewtex/tmux-mem-cpu-load'

# Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
run '~/.tmux/plugins/tpm/tpm'

