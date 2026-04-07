pub fn isCombiningMark(cp: u21) bool {
    if (cp < 0x0300 or cp > 0xFE2F) return false;
    return (cp <= 0x036F)
        or (cp >= 0x0483 and cp <= 0x0489)
        or (cp >= 0x0591 and cp <= 0x05C7)
        or (cp >= 0x0610 and cp <= 0x061A) or (cp >= 0x064B and cp <= 0x065F)
        or cp == 0x0670 or (cp >= 0x06D6 and cp <= 0x06ED) or cp == 0x0711
        or (cp >= 0x0730 and cp <= 0x074A)
        or (cp >= 0x07A6 and cp <= 0x07B0) or (cp >= 0x07EB and cp <= 0x07F3)
        or (cp >= 0x0816 and cp <= 0x082D) or (cp >= 0x0859 and cp <= 0x085B)
        or (cp >= 0x0898 and cp <= 0x08E1) or (cp >= 0x08E3 and cp <= 0x0963)
        or (cp >= 0x0901 and cp <= 0x0903) or (cp >= 0x093A and cp <= 0x094F)
        or (cp >= 0x0951 and cp <= 0x0957) or (cp >= 0x0962 and cp <= 0x0963)
        or (cp >= 0x0981 and cp <= 0x0983) or (cp >= 0x09BC and cp <= 0x09CD)
        or cp == 0x09D7 or (cp >= 0x09E2 and cp <= 0x09E3)
        or (cp >= 0x0A01 and cp <= 0x0A75)
        or (cp >= 0x0A81 and cp <= 0x0AFF)
        or cp == 0x0B82 or (cp >= 0x0BBE and cp <= 0x0BC8)
        or (cp >= 0x0BCA and cp <= 0x0BCD) or cp == 0x0BD7
        or (cp >= 0x0C00 and cp <= 0x0C04) or (cp >= 0x0C3E and cp <= 0x0C56)
        or (cp >= 0x0C62 and cp <= 0x0C63)
        or (cp >= 0x0C81 and cp <= 0x0C83) or (cp >= 0x0CBC and cp <= 0x0CD6)
        or (cp >= 0x0CE2 and cp <= 0x0CE3)
        or (cp >= 0x0D00 and cp <= 0x0D03) or (cp >= 0x0D3B and cp <= 0x0D4E)
        or cp == 0x0D57 or (cp >= 0x0D62 and cp <= 0x0D63)
        or (cp >= 0x0DCA and cp <= 0x0DDF) or (cp >= 0x0DF2 and cp <= 0x0DF3)
        or cp == 0x0E31 or (cp >= 0x0E34 and cp <= 0x0E3A)
        or (cp >= 0x0E47 and cp <= 0x0E4E)
        or cp == 0x0EB1 or (cp >= 0x0EB4 and cp <= 0x0EB9)
        or (cp >= 0x0EBB and cp <= 0x0EBC) or (cp >= 0x0EC8 and cp <= 0x0ECD)
        or (cp >= 0x0F18 and cp <= 0x0F19) or cp == 0x0F35 or cp == 0x0F37 or cp == 0x0F39
        or (cp >= 0x0F71 and cp <= 0x0F84) or (cp >= 0x0F86 and cp <= 0x0FBC)
        or (cp >= 0x102B and cp <= 0x103E) or (cp >= 0x1056 and cp <= 0x1059)
        or (cp >= 0x105E and cp <= 0x1060) or (cp >= 0x1062 and cp <= 0x106D)
        or (cp >= 0x1AB0 and cp <= 0x1ACE)
        or (cp >= 0x1DC0 and cp <= 0x1DFF)
        or (cp >= 0x20D0 and cp <= 0x20F0)
        or (cp >= 0xFE20 and cp <= 0xFE2F);
}

pub fn isZeroWidth(cp: u21) bool {
    if (cp == 0xFE0F) return true;
    if (cp == 0x200D) return true;
    if (cp == 0x20E3) return true;
    if (cp >= 0xFE00 and cp <= 0xFE0E) return true;
    if (cp >= 0x1F3FB and cp <= 0x1F3FF) return true;
    return false;
}

pub fn charDisplayWidth(char: u21) u2 {
    const cp: u32 = char;
    if (cp < 0x1100) return 1;
    if (cp <= 0x115F) return 2;
    if (cp == 0x2329 or cp == 0x232A) return 2;
    if (cp >= 0x2E80 and cp <= 0x303E) return 2;
    if (cp >= 0x3041 and cp <= 0x33FF) return 2;
    if (cp >= 0x3400 and cp <= 0x4DBF) return 2;
    if (cp >= 0x4E00 and cp <= 0x9FFF) return 2;
    if (cp >= 0xA000 and cp <= 0xA4CF) return 2;
    if (cp >= 0xA960 and cp <= 0xA97F) return 2;
    if (cp >= 0xAC00 and cp <= 0xD7AF) return 2;
    if (cp >= 0xF900 and cp <= 0xFAFF) return 2;
    if (cp >= 0xFE10 and cp <= 0xFE6F) return 2;
    if (cp >= 0xFF01 and cp <= 0xFF60) return 2;
    if (cp >= 0xFFE0 and cp <= 0xFFE6) return 2;
    if (cp >= 0x1B000 and cp <= 0x1B2FF) return 2;
    if (cp >= 0x1F300 and cp <= 0x1F64F) return 2;
    if (cp >= 0x1F680 and cp <= 0x1F6FF) return 2;
    if (cp >= 0x1F7E0 and cp <= 0x1F7FF) return 2;
    if (cp >= 0x1F900 and cp <= 0x1FAFF) return 2;
    if (cp >= 0x20000 and cp <= 0x2FFFD) return 2;
    if (cp >= 0x30000 and cp <= 0x3FFFD) return 2;
    if (cp == 0x1F004 or cp == 0x1F0CF or cp == 0x1F18E) return 2;
    if (cp >= 0x1F191 and cp <= 0x1F19A) return 2;
    if (cp == 0x1F201 or cp == 0x1F202 or cp == 0x1F21A or cp == 0x1F22F) return 2;
    if (cp >= 0x1F232 and cp <= 0x1F23A) return 2;
    if (cp >= 0x1F250 and cp <= 0x1F251) return 2;
    return 1;
}

pub fn isTextDefaultEmoji(cp: u21) bool {
    if (charDisplayWidth(cp) == 2) return false;
    if (cp == 0x00A9 or cp == 0x00AE) return true;
    if (cp == 0x203C or cp == 0x2049) return true;
    if (cp == 0x2122 or cp == 0x2139) return true;
    if (cp >= 0x2194 and cp <= 0x2199) return true;
    if (cp == 0x21A9 or cp == 0x21AA) return true;
    if (cp >= 0x2300 and cp <= 0x23FF) return true;
    if (cp == 0x24C2) return true;
    if (cp >= 0x25AA and cp <= 0x25FF) return true;
    if (cp >= 0x2600 and cp <= 0x27BF) return true;
    if (cp >= 0x2934 and cp <= 0x2935) return true;
    if (cp >= 0x2B00 and cp <= 0x2BFF) return true;
    if (cp == 0x3030 or cp == 0x303D or cp == 0x3297 or cp == 0x3299) return true;
    if (cp >= 0x1F000 and cp <= 0x1FAFF) return true;
    return false;
}

const testing = @import("std").testing;

test "unicode width and emoji helpers" {
    try testing.expect(isCombiningMark(0x0301));
    try testing.expect(isZeroWidth(0xFE0F));
    try testing.expectEqual(@as(u2, 2), charDisplayWidth(0x1F916));
    try testing.expect(isTextDefaultEmoji(0x2733));
}
