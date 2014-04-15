#!/bin/bash -ex

cd "$(dirname "${0}")"

usage() {
    echo "Usage: $0 -s -u -c -r -f"
    echo "   -s: show_revisions only"
    echo "   -u: update only"
    echo "   -c: checkconfig only"
    echo "   -r: reconfig only"
    echo "   -f: full reconfig (show_revisions update checkconfig reconfig)"
    echo ""
    echo "   You must specify at least one option. You can also specify multiple options."
    echo "   e.g. $0 -s -r"
}

# var for session name (to avoid repeated occurences)
sn=reconfigsession
venv_cmd="workon buildduty"
reconfig_cmds=""

while getopts ":sucrf" opt; do
    case $opt in
	s)
	    reconfig_cmds="${reconfig_cmds} show_revisions"
	    ;;
	u)
	    reconfig_cmds="${reconfig_cmds} update"
	    ;;
	c)
	    reconfig_cmds="${reconfig_cmds} checkconfig"
	    ;;
	r)
	    reconfig_cmds="${reconfig_cmds} reconfig"
	    ;;
	f)
	    reconfig_cmds="show_revisions update checkconfig reconfig"
	    ;;
	?)
	    usage
	    exit 1
	    ;;
    esac
done

if [ "${reconfig_cmds}" == "" ]; then
  usage
  exit 1
fi

# Start the session and window 0 in /etc
#   This will also be the default cwd for new windows created
#   via a binding unless overridden with default-path.
tmux attach -t "$sn" || tmux new-session -s "$sn" -n etc -d
#tmux set -g set-remain-on-exit on

tmux new-window -t "$sn" -n "reconfig"
tmux split-window -t 0 -h -p 50
tmux split-window -t 0 -v -p 80
tmux split-window -t 2 -v -p 50
tmux split-window -t 1 -v -p 20
tmux split-window -t 1 -v -p 25
tmux split-window -t 1 -v -p 33
tmux split-window -t 1 -v -p 50

for i in {0..7}; do
    tmux select-pane -t $i
    #tmux send-keys -t 1 "echo This is pane $i" C-m
    tmux send-keys -t $i "${venv_cmd}" C-m
done

tmux select-pane -t 0
tmux send-keys -t 0 "python manage_masters.py -f production-masters.json -j16 -R scheduler ${reconfig_cmds}" C-m
tmux select-pane -t 2
tmux send-keys -t 2 "python manage_masters.py -f production-masters.json -j16 -R build ${reconfig_cmds}" C-m
tmux select-pane -t 3
tmux send-keys -t 3 "python manage_masters.py -f production-masters.json -j16 -R try ${reconfig_cmds}" C-m
tmux select-pane -t 1
tmux send-keys -t 1 "python manage_masters.py -f production-masters.json -j16 -M linux ${reconfig_cmds}" C-m
tmux select-pane -t 7
tmux send-keys -t 7 "python manage_masters.py -f production-masters.json -j16 -M macosx ${reconfig_cmds}" C-m
tmux select-pane -t 6
tmux send-keys -t 6 "python manage_masters.py -f production-masters.json -j16 -M panda ${reconfig_cmds}" C-m
tmux select-pane -t 5
tmux send-keys -t 5 "python manage_masters.py -f production-masters.json -j16 -M tegra ${reconfig_cmds}" C-m
tmux select-pane -t 4
tmux send-keys -t 4 "python manage_masters.py -f production-masters.json -j16 -M windows ${reconfig_cmds}" C-m

# Set the default cwd for new windows (optional, otherwise defaults to session cwd)
#tmux set-option default-path /

# Select window #1 and attach to the session
tmux select-window -t "$sn"
tmux -2 attach-session -t "$sn"
