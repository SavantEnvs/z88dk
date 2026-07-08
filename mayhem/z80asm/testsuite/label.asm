start:
    ld hl,msg
    call print
    ret
msg:
    defb "hi",0
print:
    ret
