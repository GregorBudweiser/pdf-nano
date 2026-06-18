#pragma once

// All error codes (now and in the future) are guaranteed to be smaller than 0
enum Errors {
    OUT_OF_MEMORY = -1,
    NON_UTF8_TEXT = -2,

    // JPEG related errors
    J_NOT_A_JPEG = -10,
    J_TRUNCATED = -11,
    J_UNSUPPORTED = -12
};