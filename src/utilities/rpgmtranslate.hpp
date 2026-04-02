#pragma once

#include "rpgmtranslate.h"

#include <qcompilerdetection.h>

//! MSVC needs equality operators for some reason, while glibc doesn't.
#ifdef Q_CC_MSVC
[[nodiscard]] auto operator==(const FFIString& lhs, const FFIString& rhs)
    -> bool {
    return lhs.ptr == rhs.ptr && lhs.len == rhs.len;
};

[[nodiscard]] auto operator==(const ByteBuffer& lhs, const ByteBuffer& rhs)
    -> bool {
    return lhs.ptr == rhs.ptr && lhs.len == rhs.len;
};
#endif