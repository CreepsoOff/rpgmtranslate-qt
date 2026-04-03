#pragma once

#include "rpgmtranslate.h"

#include <qcompilerdetection.h>

//! GCC 14 and MSVC need those operators. GCC 15 doesn't and I'm not sure why.

[[nodiscard]] inline auto operator==(const FFIString& lhs, const FFIString& rhs)
    -> bool {
    return lhs.ptr == rhs.ptr && lhs.len == rhs.len;
};

[[nodiscard]] inline auto
operator==(const ByteBuffer& lhs, const ByteBuffer& rhs) -> bool {
    return lhs.ptr == rhs.ptr && lhs.len == rhs.len;
};