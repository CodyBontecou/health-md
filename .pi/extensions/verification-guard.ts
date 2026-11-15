import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
import { fileURLToPath } from 'node:url';
import { installVerificationGuard } from '../../scripts/verification-pi.mjs';

export default function verificationGuard(pi: ExtensionAPI, root = fileURLToPath(new URL('../../', import.meta.url))) {
  installVerificationGuard(pi, root);
}
