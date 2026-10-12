### User options ###

declare-option -docstring %{
If set to a client name, the message at a main cursor in mblaze-show buffers
will be rendered there.
} str mblaze_autoshow_client

declare-option -docstring %{
When 'mblaze_autoshow_client' is set, this holds arguments to pass to
'mblaze-show' when rendering the *mblaze-auto-show* buffer.
} str-list mblaze_autoshow_arguments

define-command mblaze-open-mime-part -params 3 -docstring %{
mblaze-open-mime-part <message_file> <part> <mime_type>: overridable callback for opening a MIME part.
Called by mblaze-open-named-mime-parts and mblaze-open-html-mime-part.
Override this command to choose how parts are opened.
} %{
    fail %{mblaze-open-mime-part not implemented; see 'doc mblaze mime-parts'}
}

#### Listing and showing messages ###

define-command mblaze-scan -params 1 -docstring %{
mblaze-scan <shell_script>: populate a new scratch buffer with the output of
'<shell_script> | mscan'

The message at a main cursor in the *mblaze-scan* buffer is displayed in
the client given by the 'mblaze_autoshow_client' option.
Set the 'mblaze_autoshow_arguments' to pass extra arguments to mshow.

Example:

    mblaze-scan %{ mlist $(mdirs) | mthread }
    new evaluate-commands %{ set-option global mblaze_autoshow_client %val{client} }
} %{
    edit! -scratch *mblaze-scan*
    mblaze-scan-populate %arg{1}
    set-option buffer mblaze_list_command %arg{1}
    add-highlighter buffer/ regex '^(?<flags>.{3}) +(?<num>\d*) +(?<date>.{10}) (?<from>.{17})' flags:red num:yellow date:blue from:green
    add-highlighter buffer/ line '%val{cursor_line}' +r
    hook buffer NormalIdle .* mblaze-scan-update-autoshow
    hook buffer GlobalSetOption mblaze_autoshow_client=.+ mblaze-scan-update-autoshow
}
complete-command mblaze-scan shell

define-command mblaze-next-thread -docstring %{
move to the next thread start in a scan buffer.
} %{
    mblaze-next-or-previous-thread next
}
define-command mblaze-previous-thread -docstring %{
move to the previous thread start in a scan buffer.
} %{
    mblaze-next-or-previous-thread previous
}

define-command mblaze-show -params .. -docstring %{
mblaze-show [<mshow_arguments>]: render context's messages in a scratch buffer.
See ':doc mblaze context's-message(s)'.
All optional arguments are forwarded to the mshow utility.
} %{
    evaluate-commands -save-regs bf %{
        set-register b %opt{mblaze_show_buffer_name}
        set-option global mblaze_show_args %arg{@}
        evaluate-commands %sh{
            set -- $(
                "${kak_opt_mblaze_source%/*}"/mblaze-current-files \
                    kak_command_fifo kak_response_fifo "$kak_selections_desc" |
                    sed "s/'/''/g; s/^/'/; s/\$/'/"
            )
            printf '%s\n' "set-register f$(for arg; do printf ' %s' "$arg"; done)"
        }
        evaluate-commands -try-client %opt{mblaze_effective_show_client} -save-regs | %{
            edit! -scratch %sh{ printf %s "${kak_reg_b:-"*mblaze-show*"}" }
            set-register | %{
                eval "set -- $kak_quoted_opt_mblaze_show_args $kak_quoted_reg_f"
                # Export the window width in case something like mflow(1)
                # is used as filter.
                COLUMNS=$kak_window_width mshow -n "$@"
            }
            execute-keys !<ret>gg
            set-option buffer filetype mail
            set-option buffer mblaze_shown_files %reg{f}
            try %{
                add-highlighter buffer/mblaze-show wrap -word -marker '↪'
            }
        }
    }
}

define-command mblaze-refresh -docstring %{
updates the current mblaze-scan buffer by re-running its command
} %{
    mblaze-apply-command-and-refresh nop
}

### Operating on messages ###

define-command mblaze-pipe-to -params 1..2 -docstring %{
mblaze-pipe-to [-thread] <shell_command>: pipe the context's messages'
filenames to a shell command.

In a scan buffer, refresh the listing afterwards.
In a scan buffer, -thread pipes entire threads.
} %{
    evaluate-commands -draft -save-regs a %{
        set-register a %arg{@}
        evaluate-commands %sh{
            echo "echo -to-file $kak_response_fifo -quoting shell -- %opt{mblaze_shown_files}" >$kak_command_fifo
            shown_files=$(cat $kak_response_fifo)
            if [ -n "$shown_files" ]; then
                if [ "$1" = -thread ]; then
                    echo 'fail -- %{-thread is not supported from a show buffer}'
                    exit
                fi
                cmd=$1
                eval "set -- $shown_files"
                mseq -f -- "$@" | eval "$cmd" >&2
            else {
                cat <<'EOF'
                mblaze-apply-command-and-refresh evaluate-commands %{
                    nop %sh{
                        eval "set -- $kak_quoted_reg_a"
                        thread=
                        if [ "$1" = -thread ]; then
                            thread=-thread
                            shift
                        fi
                        cmd=$1
                        "${kak_opt_mblaze_source%/*}"/mblaze-list-files $thread \
                            kak_command_fifo kak_response_fifo "$kak_selections_desc" |
                            eval "$cmd" >&2
                    }
                }
EOF
            } fi
        }
    }
}
complete-command mblaze-pipe-to shell

define-command mblaze-refile -params 1..2 -docstring %{
mblaze-refile [-thread] <maildir_folder>: move selected messages to a maildir folder.

move the context's messages to <maildir_folder>. With -thread, move entire threads.
} %{
    evaluate-commands %sh{
        thread=
        dest=%arg{1}
        if [ $# -eq 2 ]; then {
            if [ "$1" != -thread ]; then {
                echo "fail %{unexpected argument}"
                exit 1
            } fi
            dest=%arg{2}
            thread=-thread
        } fi
        echo "mblaze-pipe-to $thread %exp{ mrefile $dest }"
    }
}
complete-command mblaze-refile shell-script-candidates %{
    has_thread=false
    for arg; do
        if [ "$arg" = -thread ]; then has_thread=true; fi
    done
    if ! $has_thread; then
        echo -thread
    fi
    mdirs
}

### Writing messages ###

define-command mblaze-compose -params .. -docstring %{
mblaze-compose [<mcom_arguments>]: compose a new message.
All optional arguments are forwarded to mcom.
} %{
    mblaze-draft-start mcom %arg{@}
}

define-command mblaze-reply -params .. -docstring %{
mblaze-reply [<mrep_arguments>]: reply to the context's message.

In a show buffer, reply to its single message.
In a scan buffer, reply to the message at the main cursor.
All optional arguments are forwarded to mrep.
} %{
    mblaze-draft-start mrep %arg{@}
}

define-command mblaze-forward -params .. -docstring %{
mblaze-forward [<mfwd_arguments>]: forward the context's messages.

In a show buffer, forward its single message.
In a scan buffer, forward the message at the main cursor.
All optional arguments are forwarded to mfwd.
} %{
    mblaze-draft-start mfwd %arg{@}
}

define-command mblaze-send -docstring %{
finish editing the current draft and have mcom/mrep/mfwd send it
} %{
    evaluate-commands %sh{
        if [ -z "$kak_opt_mblaze_mcom_dir" ]; then
            echo 'fail %{must be called in a buffer created by mblaze-compose, mblaze-reply or mblaze-forward}'
        fi
    }
    write -method replace
    remove-hooks buffer mblaze-draft-cancel
    mblaze-draft-finish send
    delete-buffer
    echo -markup '{Information}Message sent'
}

### MIME parts ###

define-command mblaze-open-named-mime-parts -params 1.. -docstring %{
mblaze-open-named-mime-parts <part_filenames>...:
for each argument, call mblaze-open-mime-part with three arguments:
1. the context's message's filename
2. the given part filename argument
3. its MIME type.
} %{
    evaluate-commands %sh{
        message_file=$("${kak_opt_mblaze_source%/*}"/mblaze-current-files \
            kak_command_fifo kak_response_fifo "${kak_selections_desc%% *}")
        if [ -z "$message_file" ]; then
            echo 'fail %{missing message file, see :doc mblaze messages-in-context}'
            exit 1
        fi
        kakquote() {
            printf "%s" "$1" | sed "s/'/''/g; 1s/^/'/; \$s/\$/'/"
        }
        mshow=$(mshow -n -t "$message_file")
        for i in $(seq $#)
        do
            eval "name=\$$i"
            mime_type=$(
                printf %s "$mshow" | awk -v"name=$name" '
                    NR != 1 && /name=/ {
                        mime_type = $2
                        gsub(/.*name="|"$/, "")
                        if ($0 == name) {
                            print mime_type
                        }
                    }
                '
            )
            printf '%s\n' "mblaze-open-mime-part $(kakquote "$message_file") %arg{$i} $(kakquote "$mime_type")"
        done
    }
}
complete-command mblaze-open-named-mime-parts shell-script-candidates %{
    tmpdir=$(mktemp -d ${TMPDIR:-/tmp}/kakoune-mblaze-open-named-mime-parts.XXXXXX)
    mkfifo $tmpdir/fifo
    echo 'evaluate-commands -client '$kak_client' %{
        nop %sh{
            set -- $("${kak_opt_mblaze_source%/*}"/mblaze-current-files \
                        kak_command_fifo kak_response_fifo "${kak_selections_desc%% *}")
            [ $# -eq 1 ] || exit
            mshow -n -t "$1" | awk '\''
                NR != 1 && /name=/ {
                    gsub(/.*name="|"$/, "")
                    print
                }
            '\'' >'$tmpdir/fifo'
        }
    }' | kak -p $kak_session
    cat $tmpdir/fifo
    rm $tmpdir/fifo
    rmdir $tmpdir
}

define-command mblaze-open-html-mime-part -docstring %{
Provided the context's message has a single unnamed text/html MIME part,
call mblaze-open-mime-part with three arguments:
1. the message filename
2. the part number
3. the MIME type ('text/html')
} %{
    evaluate-commands %sh{
        message_file=$("${kak_opt_mblaze_source%/*}"/mblaze-current-files \
            kak_command_fifo kak_response_fifo "${kak_selections_desc%% *}" | sed -n '1p')
        if [ -z "$message_file" ]; then
            echo "fail %{missing message file, see :doc mblaze messages-in-context}"
            exit 1
        fi
        html_part=$(
            mshow -n -t "$message_file" |
                awk  '$2 == "text/html" && !/name=/ { print $1 }'
        )
        if [ -z "$html_part" ]; then
            echo "fail %{message has no unnamed text/html MIME part}"
            exit
        fi
        if ! printf %s "$html_part" | grep -q '^[0-9]\+:$'; then
            echo "fail %{message contains multiple unnamed text/html MIME parts}"
            exit
        fi
        kakquote() {
            printf "%s" "$1" | sed "s/'/''/g; 1s/^/'/; \$s/\$/'/"
        }
        printf '%s\n' "mblaze-open-mime-part $(kakquote "$message_file") ${html_part%:} text/html"
    }
}

### Helpers ###

define-command -hidden mblaze-scan-populate -params 1 %{
    evaluate-commands -save-regs a| %{
        set-register a %arg{1}
        set-register | %exp{
            exec <&-
            files=$(
                %arg{1}
            )
            %{
                echo >${kak_command_fifo} "set-option buffer mblaze_scanned_files $(
                    printf %s "$files" | sed "s/'/''/g; s/^/'/; s/$/'/" | tr '\n' ' '
                )"
                printf %s "$files" | COLUMNS=100000 mscan
            }
        }
        set-option buffer readonly false
        execute-keys '%|<ret>gg'
        set-option buffer readonly true
    }
}

define-command -hidden mblaze-scan-update-autoshow %{
    try %{
        evaluate-commands -client %opt{mblaze_autoshow_client} fail
    } catch %{
        # Failed successfullly, so our show client is defined.
        set-option local mblaze_effective_show_client %opt{mblaze_autoshow_client}
        set-option local mblaze_show_buffer_name *mblaze-show-auto*
        mblaze-show %opt{mblaze_autoshow_arguments}
    }
}

define-command -hidden mblaze-apply-command-and-refresh -params 1.. %{
    evaluate-commands -save-regs s %{
        set-register s %val{selections_desc}
        %arg{@}
        set-option buffer readonly false
        mblaze-scan-populate %opt{mblaze_list_command}
        select %reg{s}
        echo -markup {Information}reloaded
    }
}

define-command -hidden mblaze-draft-start -params 1.. %{
    evaluate-commands %sh{
        for arg
        do
            if [ "$arg" = -send ]; then
                echo 'fail %{the -send option is not supported, use mblaze-send instead}'
                exit
            fi
        done
        kakquote() {
            printf "%s" "$1" | sed "s/'/''/g; 1s/^/'/; \$s/\$/'/"
        }
        case "$1" in (mrep | mfwd) {
            if ! message_files=$("${kak_opt_mblaze_source%/*}"/mblaze-current-files \
                kak_command_fifo kak_response_fifo "${kak_selections_desc%% *}")
            then {
                echo 'fail %{failed to find message file}'
                exit
            } fi
            if [ -z "$message_files" ]; then
                echo 'fail %{missing message file, see :doc mblaze messages-in-context}'
                exit
            fi
            ifs=$IFS
            IFS=$'\n'
            set -- "$@" -- $message_files
            IFS=$ifs
        } ;; esac
        mcom_dir=$(mktemp -d "${TMPDIR:-/tmp}/kakoune-mblaze-"$1".XXXXXX")
        editor=$mcom_dir/editor
        edit_done=$mcom_dir/editor-done
        stdin=$mcom_dir/stdin
        exit_status=$mcom_dir/exit-status
        echo >"$editor" '#!/bin/sh
echo >$kak_response_fifo "$@"
<'"$edit_done"
        mkfifo $stdin $edit_done $exit_status
        chmod +x $editor
        (
            {
                cat $stdin | MBLAZE_EDITOR=$editor "$@"
                echo $? >$exit_status
            } 2>&1 |
                sed 's/^What now? ([^)]*) //' |
                while IFS=$'\n' read -r line
            do
                printf %s "echo -debug $(kakquote "$1 output: $line")" | kak -p $kak_session
            done
        ) </dev/null >/dev/null 2>&1 &
        draft=$(cat $kak_response_fifo)
        printf %s "
            edit $(kakquote "$draft")
            set-option buffer mblaze_mcom_dir $(kakquote "$mcom_dir")
            hook -always -once -group mblaze-draft-cancel buffer BufClose .* %{
                mblaze-draft-finish cancel
            }
        "
    }
}

define-command -hidden mblaze-draft-finish -params 1 %{
    evaluate-commands %sh{
        mcom_dir=$kak_opt_mblaze_mcom_dir
        >"$mcom_dir/editor-done"
        printf '%s\n' "$1" >"$mcom_dir/stdin"
        echo "unset-option buffer mblaze_mcom_dir" # double send is not supported
        if [ "$(cat "$mcom_dir/exit-status")" != 0 ] && [ "$1" = send ]; then
            echo "
                edit!
                fail %{failed to send message, see *debug* buffer}"
            exit
        fi
        rm "$mcom_dir/editor" "$mcom_dir/editor-done" "$mcom_dir/stdin" "$mcom_dir/exit-status"
        rmdir "$mcom_dir"
    }
}

define-command -hidden mblaze-next-or-previous-thread -params 1 %{
    execute-keys ,
    evaluate-commands %sh{
        mode=$1
        if [ "$mode" = next ]; then
            plus_minus=+ movement=j limit=$kak_buf_line_count
        else
            plus_minus=- movement=k limit=1
        fi
        echo "echo -to-file $kak_response_fifo -quoting shell -- %opt{mblaze_scanned_files}" >$kak_command_fifo
        eval "set -- $(cat $kak_response_fifo)"
        i=$kak_cursor_line
        delta=0
        while [ $i -ne $limit ]
        do
            i=$((i $plus_minus 1))
            delta=$((delta + 1))
            eval "line=\${$i}"
            if [ "$line" = "${line# }" ]; then
                break
            fi
        done
        if [ $delta -ne 0 ]; then
            echo execute-keys ${delta}${movement}
        fi
    }
}

declare-option -hidden str mblaze_source %val{source}

# For mblaze-scan
declare-option -hidden str-list mblaze_scanned_files
declare-option -hidden str-list mblaze_list_command

# For mblaze-show
declare-option -hidden str-list mblaze_show_args
declare-option -hidden str-list mblaze_shown_files
declare-option -hidden str mblaze_effective_show_client
declare-option -hidden str mblaze_show_buffer_name

# For mblaze-compose, mblaze-reply, mblaze-forward, mblaze-send
declare-option -hidden str mblaze_mcom_dir
