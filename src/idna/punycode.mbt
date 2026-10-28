// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Punycode's parameters (RFC 3492 §5). Every one of them is fixed by the
/// encoding; they are named here because the algorithm is unreadable otherwise.
const BASE : Int32 = 36

///|
const TMIN : Int32 = 1

///|
const TMAX : Int32 = 26

///|
const SKEW : Int32 = 38

///|
const DAMP : Int32 = 700

///|
const INITIAL_BIAS : Int32 = 72

///|
const INITIAL_N : Int32 = 128

///|
/// The highest code point there is.
const CEILING : Int32 = 0x10FFFF

///|
/// As far as an intermediate count may go: half the range of a 32-bit integer,
/// which every target can hold.
const BOUND : Int32 = 0x3FFFFFFF

///|
/// Why a label is not Punycode.
pub(all) suberror Refused {
  /// A character that is not a Punycode digit, at this offset.
  Digit(at~ : Int32)
  /// A number that runs past the code space, at this offset.
  Overflow(at~ : Int32)
} derive(Eq, Debug)

///|
pub extend Refused with Eq::{equal, not_equal}

///|
pub extend Refused with Debug::{to_repr}

///|
/// Encode one label (RFC 3492 §6.3).
///
/// The label is not split and no `xn--` is written: that prefix belongs to
/// UTS 46, which decides when a label needs encoding at all.
pub fn encode(text : StringView) -> String {
  let points : Array[Int32] = []
  for character in text {
    points.push(character.to_int())
  }
  let out = StringBuilder()
  let mut basic = 0
  for point in points {
    if point < 0x80 {
      out.write_char(point.unsafe_to_char())
      basic += 1
    }
  }
  let total = points.length()
  let mut handled = basic
  // A label with no ASCII at all has no delimiter: `-` would read as one.
  if basic > 0 {
    out.write_char('-')
  }
  let mut n = INITIAL_N
  let mut delta = 0
  let mut bias = INITIAL_BIAS
  while handled < total {
    let mut m = CEILING + 1
    for point in points {
      if point >= n && point < m {
        m = point
      }
    }
    delta += (m - n) * (handled + 1)
    n = m
    for point in points {
      if point < n {
        delta += 1
      } else if point == n {
        let mut q = delta
        let mut k = BASE
        while true {
          let t = if k <= bias {
            TMIN
          } else if k >= bias + TMAX {
            TMAX
          } else {
            k - bias
          }
          if q < t {
            break
          }
          out.write_char(digit(t + (q - t) % (BASE - t)))
          q = (q - t) / (BASE - t)
          k += BASE
        }
        out.write_char(digit(q))
        bias = adapt(delta, handled + 1, handled == basic)
        delta = 0
        handled += 1
      }
    }
    delta += 1
    n += 1
  }
  out.to_string()
}

///|
/// Decode one label (RFC 3492 §6.2).
///
/// Both cases of digit are accepted: a name may have been upper-cased on its
/// way here, and case carries nothing in Punycode.
pub fn decode(text : StringView) -> String raise Refused {
  let input : Array[Int32] = []
  for character in text {
    input.push(character.to_int())
  }
  let length = input.length()
  let mut delimiter = -1
  for i = 0; i < length; i = i + 1 {
    if input[i] == 0x2D {
      delimiter = i
    }
  }
  let out : Array[Int32] = []
  let mut at = 0
  if delimiter >= 0 {
    for i = 0; i < delimiter; i = i + 1 {
      guard input[i] < 0x80 else { raise Digit(at=i) }
      out.push(input[i])
    }
    at = delimiter + 1
  }
  let mut n = INITIAL_N
  let mut i = 0
  let mut bias = INITIAL_BIAS
  while at < length {
    let start = i
    let mut weight = 1
    let mut k = BASE
    while true {
      guard at < length else { raise Digit(at~) }
      let d = value(input[at])
      guard d >= 0 else { raise Digit(at~) }
      at += 1
      // `i` is a delta, not a code point: it may run well past the code space
      // before the division below brings it back. Only overflow is an error.
      guard d <= (BOUND - i) / weight else { raise Overflow(at=at - 1) }
      i += d * weight
      let t = if k <= bias {
        TMIN
      } else if k >= bias + TMAX {
        TMAX
      } else {
        k - bias
      }
      if d < t {
        break
      }
      guard weight <= BOUND / (BASE - t) else { raise Overflow(at~) }
      weight *= BASE - t
      k += BASE
    }
    let size = out.length() + 1
    bias = adapt(i - start, size, start == 0)
    n += i / size
    guard n <= CEILING && (n < 0xD800 || n > 0xDFFF) else {
      raise Overflow(at~)
    }
    i = i % size
    out.insert(i, n)
    i += 1
  }
  let text = StringBuilder()
  for point in out {
    text.write_char(point.unsafe_to_char())
  }
  text.to_string()
}

///|
/// The bias after `points` code points have been handled (RFC 3492 §6.1).
fn adapt(delta : Int32, points : Int32, first : Bool) -> Int32 {
  let mut delta = if first { delta / DAMP } else { delta / 2 }
  delta += delta / points
  let mut k = 0
  while delta > (BASE - TMIN) * TMAX / 2 {
    delta /= BASE - TMIN
    k += BASE
  }
  k + (BASE - TMIN + 1) * delta / (delta + SKEW)
}

///|
/// The digit that stands for `value`: `a` to `z`, then `0` to `9`.
fn digit(value : Int32) -> Char {
  if value < 26 {
    (0x61 + value).unsafe_to_char()
  } else {
    (0x30 + value - 26).unsafe_to_char()
  }
}

///|
/// What a digit character stands for, either case, or `-1`.
fn value(character : Int32) -> Int32 {
  if character >= 0x61 && character <= 0x7A {
    character - 0x61
  } else if character >= 0x41 && character <= 0x5A {
    character - 0x41
  } else if character >= 0x30 && character <= 0x39 {
    character - 0x30 + 26
  } else {
    -1
  }
}
