package tech.loveace.appv3.util

import org.junit.Assert.assertEquals
import org.junit.Test

class InputNormalizerTest {

    @Test
    fun convertsFullWidthDigitsLettersAndPunctuation() {
        assertEquals("2024", "２０２４".toHalfWidth())
        assertEquals("abcABC", "ａｂｃＡＢＣ".toHalfWidth())
        assertEquals("pa55?", "ｐａ５５？".toHalfWidth())
        assertEquals("hello world", "hello\u3000world".toHalfWidth())
    }

    @Test
    fun keepsChineseAndRegularAsciiUntouched() {
        assertEquals("张三202", "张三202".toHalfWidth())
        assertEquals("", "".toHalfWidth())
        assertEquals("a1@", "a1@".toHalfWidth())
    }

    @Test
    fun mixedTypingNormalizesContinuously() {
        assertEquals("2024abc", "２０２４ａｂc".toHalfWidth())
    }
}
