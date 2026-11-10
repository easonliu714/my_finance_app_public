package me.movenext.flutter_pdf_text

import java.security.MessageDigest

/** Diagnostic-only, read-bounded prefix range candidate. Never a formal award verdict. */
internal class LabL1PrefixBounds(
  private val cache: MutableMap<Key, Entry> = mutableMapOf(),
  private val readBudget: Int = 64
) {
  data class Identity(
    val period: String,
    val prize: String,
    val sourceSha256: String,
    val parserVersion: String,
    val pageCount: Int,
    val tokensPerPage: Int
  )

  /** Must be backed by an independent, full-source audit; sampled binary pages do not prove it. */
  data class OrderProof(
    val identity: Identity,
    val fullCoverage: Boolean,
    val crossPageMonotonic: Boolean,
    val completeTokens: Boolean,
    val independentSourceHash: Boolean
  )

  data class Key(val identity: Identity, val prefix: String)
  data class Entry(val first: Int, val last: Int, val empty: Boolean, val digest: String)

  sealed class Outcome {
    data class Range(
      val first: Int, val last: Int, val pageReads: Int,
      val cacheHit: Boolean, val authoritative: Boolean
    ) : Outcome()
    data class Empty(val pageReads: Int, val cacheHit: Boolean) : Outcome()
    data class Hold(val reason: String, val pageReads: Int) : Outcome()
  }

  fun locate(
    identity: Identity,
    prefix: String,
    proof: OrderProof?,
    readPage: (Int) -> List<String>
  ): Outcome {
    if (!Regex("[0-9]{3}-[0-9]{2}-[0-9]{2}").matches(identity.period) ||
      identity.prize != "cloud500" ||
      !Regex("[0-9a-f]{64}").matches(identity.sourceSha256) ||
      !Regex("[A-Za-z0-9._-]{1,40}").matches(identity.parserVersion) ||
      identity.pageCount !in 1..100000 || identity.tokensPerPage !in 1..50 ||
      !Regex("[A-Z]{2}").matches(prefix) || readBudget !in 1..128
    ) return Outcome.Hold("L1_PREFIX_IDENTITY_OR_INPUT_INVALID", 0)

    val trusted = proof != null && proof.identity == identity && proof.fullCoverage &&
      proof.crossPageMonotonic && proof.completeTokens && proof.independentSourceHash
    if (proof != null && !trusted) return Outcome.Hold("L1_PREFIX_ORDER_PROOF_INVALID", 0)
    val key = Key(identity, prefix)
    cache[key]?.let { saved ->
      if (!trusted) return Outcome.Hold("L1_PREFIX_CACHE_PROOF_REQUIRED", 0)
      if (saved.digest != digest(key, saved.first, saved.last, saved.empty) ||
        (saved.empty && (saved.first != 0 || saved.last != 0)) ||
        (!saved.empty && (saved.first !in 1..identity.pageCount ||
          saved.last !in saved.first..identity.pageCount))
      ) return Outcome.Hold("L1_PREFIX_CACHE_CORRUPT", 0)
      return if (saved.empty) Outcome.Empty(0, true)
      else Outcome.Range(saved.first, saved.last, 0, true, true)
    }

    val seen = mutableMapOf<Int, List<String>>()
    var reads = 0
    fun sample(page: Int): List<String> {
      seen[page]?.let { return it }
      if (reads >= readBudget) throw IllegalStateException("L1_PREFIX_READ_BUDGET")
      reads++
      val tokens = readPage(page)
      if (tokens.size != identity.tokensPerPage ||
        tokens.any { !Regex("[A-Z]{2}[0-9]{8}").matches(it) } ||
        tokens.zipWithNext().any { (a, b) -> a >= b }
      ) throw IllegalStateException("L1_PREFIX_PAGE_INVALID")
      seen[page - 1]?.let { if (it.last() >= tokens.first())
        throw IllegalStateException("L1_PREFIX_CROSS_PAGE_NONMONOTONIC") }
      seen[page + 1]?.let { if (tokens.last() >= it.first())
        throw IllegalStateException("L1_PREFIX_CROSS_PAGE_NONMONOTONIC") }
      seen[page] = tokens
      return tokens
    }

    return try {
      val lower = prefix + "00000000"
      val upper = prefix + "99999999"
      var low = 1
      var high = identity.pageCount
      var first = identity.pageCount + 1
      while (low <= high) {
        val middle = low + ((high - low) ushr 1)
        if (sample(middle).last() >= lower) {
          first = middle
          high = middle - 1
        } else low = middle + 1
      }
      low = 1
      high = identity.pageCount
      var last = 0
      while (low <= high) {
        val middle = low + ((high - low) ushr 1)
        if (sample(middle).first() <= upper) {
          last = middle
          low = middle + 1
        } else high = middle - 1
      }
      if (first > last) {
        if (!trusted) Outcome.Hold("L1_PREFIX_EMPTY_UNATTESTED", reads)
        else {
          cache[key] = Entry(0, 0, true, digest(key, 0, 0, true))
          Outcome.Empty(reads, false)
        }
      } else {
        if (trusted) cache[key] = Entry(first, last, false, digest(key, first, last, false))
        Outcome.Range(first, last, reads, false, trusted)
      }
    } catch (error: Exception) {
      Outcome.Hold(
        if (error is IllegalStateException && error.message?.startsWith("L1_PREFIX_") == true)
          error.message!! else "L1_PREFIX_READ_FAILURE", reads
      )
    }
  }

  private fun digest(key: Key, first: Int, last: Int, empty: Boolean): String {
    val id = key.identity
    val value = listOf(id.period, id.prize, id.sourceSha256, id.parserVersion,
      id.pageCount.toString(), id.tokensPerPage.toString(), key.prefix,
      first.toString(), last.toString(), empty.toString()).joinToString("|")
    return MessageDigest.getInstance("SHA-256")
      .digest(value.toByteArray(Charsets.UTF_8))
      .joinToString("") { "%02x".format(it.toInt() and 0xff) }
  }
}
