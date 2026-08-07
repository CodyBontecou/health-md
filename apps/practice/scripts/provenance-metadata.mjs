// Build provenance may identify reviewed source paths, but must never serialize
// arbitrary clinical/identity text from filenames or raw git-status records.
export function safeProvenanceMetadataPath(path) {
  if (typeof path !== "string" || !/^[A-Za-z0-9._/-]+$/.test(path) || /(?:patient|person|mrn|dob|ssn|email|phone|address|fullname)/i.test(path) || /(?:^|[-_/])name(?:[-_/.]|$)/i.test(path) || /\b(?:[A-Z][a-z]+[-_]){1,2}[A-Z][a-z]+\b/.test(path)) return false;
  const approvedUppercaseBasenames = new Set(["AGENTS.md", "App.tsx", "LICENSE", "LICENSES.md", "Makefile", "README.md"]);
  return path.split("/").every(segment => approvedUppercaseBasenames.has(segment) || !/^[A-Z][a-z]+(?:\.[A-Za-z0-9]+)?$/.test(segment));
}
