package com.healthmd.sharedsetup

/**
 * Portable `{{token}}`/`{{#section}}` template grammar shared by the surviving Shared Setup
 * surfaces (custom Markdown validation in the v2 profile transaction and its UI-facing twins).
 *
 * This checker is version-agnostic template syntax only: it never inspects schema shape,
 * metric identity, or sensitive material, and returns a bounded non-secret problem message or
 * null. It previously lived on the removed pre-canonical v1 codec and was relocated unchanged
 * because the v2 production transaction still depends on it.
 */
object SharedSetupTemplateSyntax {
    fun templateSyntaxProblem(text: String): String? {
        if (text.length > 65_536) return "Custom Markdown is too long."
        val token = Regex("\\{\\{([#/]?)([A-Za-z0-9_]+)\\}\\}")
        val stack = ArrayDeque<String>()
        token.findAll(text).forEach { match ->
            when (match.groupValues[1]) {
                "#" -> {
                    if (stack.isNotEmpty()) return "Nested template sections are not supported."
                    stack.addLast(match.groupValues[2])
                }
                "/" -> if (stack.removeLastOrNull() != match.groupValues[2]) {
                    return "Template sections are not balanced."
                }
            }
        }
        val unmatched = text.replace(token, "")
        if (stack.isNotEmpty() || unmatched.contains("{{") || unmatched.contains("}}")) {
            return "Template tokens are malformed."
        }
        return null
    }
}
