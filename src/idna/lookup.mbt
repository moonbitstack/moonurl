// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A status the mapping table gives a code point (UTS 46 §5). `Disallowed` is
/// only ever returned to be reported: it does not stop the conversion.
const VALID : Int32 = 0

///|
const IGNORED : Int32 = 1

///|
const MAPPED : Int32 = 2

///|
const DEVIATION : Int32 = 3

///|

///|
/// The run of `idna_range` a code point belongs to: the last one that starts at
/// or below it. The runs cover the code space without gaps, so there is no
/// upper bound to check.
fn idna_entry(point : Int32) -> Int32 {
  let mut low = 0
  let mut high = idna_range.length() - 1
  while low < high {
    let middle = (low + high + 1) / 2
    if idna_range[middle].0 <= point {
      low = middle
    } else {
      high = middle - 1
    }
  }
  low
}

///|
/// The status of a code point, and the string it maps to.
fn entry(point : Int32) -> (Int32, String) {
  let code = idna_range[idna_entry(point)].1
  (code & 7, idna_map[code >> 3])
}

///|
/// The Joining_Type ArabicShaping.txt names for a code point, or `-1` when the
/// file does not name it at all. The two cases are not the same: an unlisted
/// mark is transparent, an unlisted letter is not.
fn listed_joining(point : Int32) -> Int32 {
  if joining_range.length() == 0 || joining_range[0].0 > point {
    return -1
  }
  let mut low = 0
  let mut high = joining_range.length() - 1
  while low < high {
    let middle = (low + high + 1) / 2
    if joining_range[middle].0 <= point {
      low = middle
    } else {
      high = middle - 1
    }
  }
  if joining_range[low].0 == point {
    joining_range[low].1
  } else {
    -1
  }
}

///|
/// The Joining_Type of a character: 0 U, 1 R, 2 L, 3 D, 4 C, 5 T.
///
/// ArabicShaping.txt leaves out the marks, and the Unicode Character Database
/// fills them in as transparent: everything unlisted whose general category is
/// Mn, Me or Cf joins to neither side and does not interrupt a join.
fn joining(character : Char) -> Int32 {
  let listed = listed_joining(character.to_int())
  if listed >= 0 {
    return listed
  }
  match @moonucd.category(character) {
    Mn | Me | Cf => 5
    _ => 0
  }
}
