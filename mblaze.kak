declare-option str mblaze_inbox_cmd
declare-option str mblaze_archive_cmd
declare-option str mblaze_delete_cmd

declare-option -hidden str mblaze_show_client ''
declare-option -hidden str mblaze_last_sel ''
declare-option -hidden str-list mblaze_files

define-command mblaze-inbox %{
    edit! -scratch *mblaze-inbox*
    execute-keys '!%opt{mblaze_inbox_cmd}<a-!><ret>'
    eval -draft %{
        execute-keys '%<a-s>H'
        set-option buffer mblaze_files %val{selections}
    }
    execute-keys '%|mscan<ret>gg'
    set-option buffer readonly true

    add-highlighter buffer/ regex '^(?<flags>.{3}) +(?<num>\d*) +(?<date>.{10}) (?<from>.{17})' flags:red num:yellow date:blue from:green
    add-highlighter buffer/ line '%val{cursor_line}' +r

    map buffer normal a ':mblaze-archive<ret>'
    map buffer normal d ':mblaze-delete<ret>'

    hook buffer NormalIdle .* %{ mblaze-apply-cmd mblaze-show }
}

define-command -hidden mblaze-apply-shell -params 1 %{
    set-option global mblaze_last_sel %val{selection_desc}
    evaluate-commands -itersel -draft %{
        nop %sh{
            cmd=$1
            echo "echo -to-file $kak_response_fifo -quoting shell -- %opt{mblaze_files}" > $kak_command_fifo
            eval "set -- $(cat $kak_response_fifo)"
            shift $((kak_cursor_line - 1))
            printf '%s' "$1" | eval "$cmd"
        }
    }
    mblaze-inbox
    select %opt{mblaze_last_sel}
    execute-keys vv
}

define-command mblaze-archive %{
    mblaze-apply-shell %opt{mblaze_archive_cmd}
}

define-command mblaze-delete %{
    mblaze-apply-shell %opt{mblaze_delete_cmd}
}

define-command -hidden mblaze-apply-cmd -params 1.. %{
    evaluate-commands -itersel -draft %{
        %arg{@} %sh{
            echo "echo -to-file $kak_response_fifo -quoting shell -- %opt{mblaze_files}" > $kak_command_fifo
            eval "set -- $(cat $kak_response_fifo)"
            shift $((kak_cursor_line - 1))
            printf '%s' "$1"
        }
    }
}

define-command mblaze-show -params 1 %{
    evaluate-commands -try-client %opt{mblaze_show_client} %{
        edit! -scratch *mblaze-show*
        execute-keys "!mshow %arg{1}<ret>gg"
        set-option buffer filetype mail

        evaluate-commands -draft %{ # detect patches in mail and add diff highlighter
            execute-keys '%s^diff\b<ret>'
            add-highlighter buffer/ ref diff
        }
    }
}
