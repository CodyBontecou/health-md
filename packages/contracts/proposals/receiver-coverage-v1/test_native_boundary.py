"""Opt-in host compilation of the real Swift/Kotlin admission boundary; no apps/network.

HEALTHMD_TEST_NATIVE_BOUNDARY=1 enables native tests. Kotlin uses kotlinc on PATH,
or HEALTHMD_KOTLIN_COMPILER_CLASSPATH plus HEALTHMD_KOTLIN_STDLIB for a cached compiler.
All compiler output lives in a temporary directory and is removed after the run.
"""
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
SWIFT = ROOT / 'apps/apple/HealthMd/Shared/ReceiverCoverage/ReceiverCoveragePreflight.swift'
KOTLIN = ROOT / 'apps/android/app/src/main/java/com/healthmd/data/receivercoverage/ReceiverCoveragePreflight.kt'
BASE = dict(upload='https://EXAMPLE.com:443/upload', preflight='https://example.com/coverage',
            headers={'Authorization': 'Bearer synthetic', 'X-Tenant': 'synthetic'}, scope='scope-1',
            zone='America/Los_Angeles', settings='{"profile":"synthetic"}', refresh=1, key='01' * 32)


def configurations():
    result = [('base', BASE, True)]
    for name, changes in [
        ('path', dict(upload='https://example.com/upload2')),
        ('preflight_path', dict(preflight='https://example.com/coverage2')),
        ('port', dict(upload='https://example.com:8443/upload', preflight='https://example.com:8443/coverage')),
        ('credentials', dict(headers={'Authorization': 'Bearer rotated', 'X-Tenant': 'synthetic'})),
        ('routing', dict(headers={'Authorization': 'Bearer synthetic', 'X-Tenant': 'other'})),
        ('header_order_case', dict(headers={'x-tenant': 'synthetic', 'authorization': 'Bearer synthetic'})),
        ('scope', dict(scope='scope-2')), ('zone', dict(zone='UTC')),
        ('settings', dict(settings='{"profile":"other"}')), ('key', dict(key='02' * 32)),
        ('empty_path', dict(upload='https://example.com', preflight='https://example.com:443')),
        ('ipv4', dict(upload='https://127.0.0.1/upload', preflight='https://127.0.0.1/coverage')),
        ('zero_refresh', dict(refresh=0)), ('max_refresh', dict(refresh=30)),
        ('unicode_settings', dict(settings='{"profile":"測試"}')),
    ]:
        result.append((name, BASE | changes, True))
    invalid_urls = ['http://example.com/x', 'https://other.com/x', 'https://example.com:8443/x',
                    'https://user@example.com/x', 'https://example.com/x?q=secret', 'https://example.com/x#f',
                    'https://example.com/x?', 'https://example.com/x#', 'https://example.com/../x',
                    'https://example.com/%2e/x', 'https://example.com/x y', 'https://example.com\\evil/x',
                    'https://example.com:0/x', 'https://example.com:65536/x', 'https://example.com./x',
                    'https://例子.com/x', 'https://[::1]/x', 'https://%65xample.com/x',
                    'https://-bad.com/x', 'https://bad-.com/x', 'https://bad_host.com/x',
                    'https://example.com/[x]', 'https://example.com/|', 'https://example.com/"',
                    'https://999.999.999.999/x', 'https://0177.0.0.1/x', 'https://123/x', 'https://a.123/x']
    for i, url in enumerate(invalid_urls):
        result.append((f'bad_url_{i}', BASE | dict(preflight=url), False))
        if i != 1 and i != 2:
            result.append((f'bad_both_url_{i}', BASE | dict(upload=url, preflight=url), False))
    for i, header in enumerate(['Accept', 'Content-Type', 'Content-Length', 'Content-Encoding', 'Host',
                                'Transfer-Encoding', 'Connection', 'Trailer', 'TE', 'Upgrade', 'Expect',
                                'Proxy-Authorization', 'Proxy-Connection', 'Bad Name', 'Bäd']):
        result.append((f'bad_header_{i}', BASE | dict(headers={header: 'synthetic'}), False))
    for name, changes in [
        ('duplicate_header', dict(headers={'Authorization': 'one', 'authorization': 'two'})),
        ('header_injection', dict(headers={'X-Route': 'one\r\nOther: two'})),
        ('large_header', dict(headers={'X-Route': 'x' * 16384})),
        ('too_many_headers', dict(headers={f'X-Route-{i}': 'v' for i in range(65)})),
        ('invalid_scope', dict(scope='tenant/private')), ('empty_scope', dict(scope='')),
        ('invalid_zone', dict(zone='Invalid/Zone')), ('offset_zone', dict(zone='+01:00')),
        ('negative_refresh', dict(refresh=-1)), ('large_refresh', dict(refresh=31)),
        ('empty_key', dict(key='')), ('short_key', dict(key='01' * 31)),
        ('empty_settings', dict(settings='')),
    ]:
        result.append((name, BASE | changes, False))
    return result


def expected_binding(config):
    # Independent normative transcript oracle. URLs here have known canonical spellings.
    def normalized(url):
        from urllib.parse import urlsplit
        parts = urlsplit(url)
        port = '' if parts.port in (None, 443) else f':{parts.port}'
        return f'https://{parts.hostname.lower()}{port}{parts.path or "/"}'
    headers = sorted((key.lower(), value) for key, value in config['headers'].items())
    fields = ['receiver-coverage-destination-v1', 'compatibility_api', normalized(config['upload']),
              normalized(config['preflight']), config['scope'], config['zone'], config['settings'], str(len(headers))]
    fields.extend(item for pair in headers for item in pair)
    encoded = [field.encode() for field in fields]
    transcript = b''.join(str(len(field)).encode() + b':' + field for field in encoded)
    return hmac.new(bytes.fromhex(config['key']), transcript, hashlib.sha256).hexdigest()


OCCURRENCES = [
    ('dst', ['2026-03-06', '2026-03-08'], True, '2026-03-09'),
    ('holes', ['2026-02-10', '2026-03-08'], True, '2026-03-09'),
    ('full_window', ['2026-02-07', '2026-03-08'], True, '2026-03-09'),
    ('too_wide', ['2026-02-06', '2026-03-08'], False, None),
    ('today', ['2026-03-09'], False, None), ('future', ['2026-03-10'], False, None),
    ('bad_leap', ['2026-02-29'], False, None), ('bad_month', ['2026-13-01'], False, None),
    ('padding', ['2026-3-08'], False, None), ('duplicate', ['2026-03-08', '2026-03-08'], False, None),
    ('unsorted', ['2026-03-08', '2026-03-06'], False, None), ('empty', [], False, None),
]


def literal(value, kotlin=False):
    text = json.dumps(value, ensure_ascii=False)
    return text.replace('$', '\\$') if kotlin else text


def prepare(config, kotlin=False, default=False):
    lit = lambda value: literal(value, kotlin)
    if kotlin:
        headers = 'mapOf(' + ','.join(f'{lit(k)} to {lit(v)}' for k, v in config['headers'].items()) + ')'
        return ('ReceiverCoveragePreflight.prepare(' + ('' if default else 'policy=ReceiverCoveragePreflight.Policy.MISSING_DAYS,') +
                f'uploadUrl={lit(config["upload"])},preflightUrl={lit(config["preflight"])},uploadHeaders={headers},' +
                f'scopeId={lit(config["scope"])},calendarTimezone={lit(config["zone"])},' +
                f'frozenOutputSettings={lit(config["settings"])}.toByteArray(),refreshRecentDays={config["refresh"]},' +
                f'installationKey=hex({lit(config["key"])}))')
    headers = '[' + ','.join(f'{lit(k)}:{lit(v)}' for k, v in config['headers'].items()) + (']' if config['headers'] else ':]')
    return ('try ReceiverCoveragePreflight.prepare(' + ('' if default else 'policy: .missingDays,') +
            f'uploadURL:{lit(config["upload"])},preflightURL:{lit(config["preflight"])},uploadHeaders:{headers},' +
            f'scopeID:{lit(config["scope"])},calendarTimeZone:{lit(config["zone"])},' +
            f'frozenOutputSettings:Data({lit(config["settings"])}.utf8),refreshRecentDays:{config["refresh"]},' +
            f'installationKey:hex({lit(config["key"])}))')


def harness(kotlin=False):
    if kotlin:
        lines = ['import com.healthmd.data.receivercoverage.*', 'import java.time.Instant',
                 'fun hex(s:String)=s.chunked(2).map{it.toInt(16).toByte()}.toByteArray()', 'fun main(){']
        for name, config, _ in configurations():
            lines.append(f'try {{ println("{name}\\t"+{prepare(config, True)}!!.destinationBinding) }} catch(e:ReceiverCoveragePreflight.BoundaryException){{println("{name}\\tinvalid")}}')
        lines.append(f'check({prepare(BASE | dict(upload="http://invalid", key="", zone="invalid", refresh=-1), True, True)} == null)')
        lines.append(f'val p={prepare(BASE, True)}!!')
        lines.append('p.requireOriginalDestination(p.destinationBinding); try {p.requireOriginalDestination("changed"); error("rerouted")} catch(e:ReceiverCoveragePreflight.BoundaryException){}')
        for name, dates, _, _ in OCCURRENCES:
            array = 'listOf<String>(' + ','.join(literal(day, True) for day in dates) + ')'
            lines.append(f'try{{println("occ_{name}\\t"+java.util.Base64.getEncoder().encodeToString(p.requestBody("occurrence-1",{array},Instant.parse("2026-03-09T08:00:00Z"))))}}catch(e:ReceiverCoveragePreflight.BoundaryException){{println("occ_{name}\\tinvalid")}}')
        lines.append(f'val utc={prepare(BASE | dict(zone="UTC"), True)}!!')
        lines.append('println("utc_body\\t"+java.util.Base64.getEncoder().encodeToString(utc.requestBody("occurrence-1",listOf("2026-03-08"),Instant.parse("2026-03-09T01:00:00Z"))))')
        lines.append('try { p.requestBody("occurrence-1",listOf("2026-03-08"),Instant.parse("2026-03-09T01:00:00Z")); error("UTC date used") } catch(e:ReceiverCoveragePreflight.BoundaryException){}')
        lines.append('''
for(status in listOf(204,301,302,307,308,401,429,500)) {
    try {ReceiverCoverageResponseBuffer(status,"application/json"); error("status accepted")}
    catch(e:ReceiverCoveragePreflight.BoundaryException){}
}
for(media in listOf(null,"text/json","application/jsonp","text/html")) {
    try {ReceiverCoverageResponseBuffer(200,media); error("media accepted")}
    catch(e:ReceiverCoveragePreflight.BoundaryException){}
}
val b=ReceiverCoverageResponseBuffer(200,"Application/JSON; charset=utf-8")
b.append(ByteArray(65535)); b.append(byteArrayOf(1)); check(b.finish().size==65536)
try {b.append(byteArrayOf(2)); error("cap ignored")} catch(e:ReceiverCoveragePreflight.BoundaryException){}
try {b.finish(); error("partial evidence exposed")} catch(e:ReceiverCoveragePreflight.BoundaryException){}
try {b.append(byteArrayOf()); error("poison cleared")} catch(e:ReceiverCoveragePreflight.BoundaryException){}
println("buffer\\tok")
}''')
    else:
        lines = ['import Foundation', 'func hex(_ s:String)->Data {Data(stride(from:0,to:s.count,by:2).map { i in let start=s.index(s.startIndex,offsetBy:i); return UInt8(s[start..<s.index(start,offsetBy:2)],radix:16)! })}']
        for name, config, _ in configurations():
            lines.append(f'do {{ let p={prepare(config)}!; print("{name}\\t"+p.destinationBinding) }} catch ReceiverCoveragePreflight.BoundaryError.invalidConfiguration {{print("{name}\\tinvalid")}}')
        lines.append(f'let defaultPlan={prepare(BASE | dict(upload="http://invalid", key="", zone="invalid", refresh=-1), default=True)}; precondition(defaultPlan == nil)')
        lines.append(f'let p={prepare(BASE)}!')
        lines.append('try p.requireOriginalDestination(p.destinationBinding); do {try p.requireOriginalDestination("changed"); fatalError("rerouted")} catch ReceiverCoveragePreflight.BoundaryError.destinationChanged {}')
        for name, dates, _, _ in OCCURRENCES:
            lines.append(f'do {{ let body=try p.requestBody(requestID:"occurrence-1",candidates:{literal(dates)},now:Date(timeIntervalSince1970:1773043200)); print("occ_{name}\\t"+body.base64EncodedString()) }} catch ReceiverCoveragePreflight.BoundaryError.invalidOccurrence {{print("occ_{name}\\tinvalid")}}')
        lines.append(f'let utc={prepare(BASE | dict(zone="UTC"))}!')
        lines.append('let utcBody=try utc.requestBody(requestID:"occurrence-1",candidates:["2026-03-08"],now:Date(timeIntervalSince1970:1773018000)); print("utc_body\\t"+utcBody.base64EncodedString())')
        lines.append('do {_ = try p.requestBody(requestID:"occurrence-1",candidates:["2026-03-08"],now:Date(timeIntervalSince1970:1773018000)); fatalError("UTC date used")} catch ReceiverCoveragePreflight.BoundaryError.invalidOccurrence {}')
        lines.append('''
for status in [204,301,302,307,308,401,429,500] {
    do {_ = try ReceiverCoverageResponseBuffer(statusCode:status,contentType:"application/json"); fatalError("status accepted")}
    catch ReceiverCoveragePreflight.BoundaryError.invalidResponse {}
}
for media in [nil,"text/json","application/jsonp","text/html"] as [String?] {
    do {_ = try ReceiverCoverageResponseBuffer(statusCode:200,contentType:media); fatalError("media accepted")}
    catch ReceiverCoveragePreflight.BoundaryError.invalidResponse {}
}
var b=try ReceiverCoverageResponseBuffer(statusCode:200,contentType:"Application/JSON; charset=utf-8")
try b.append(Data(repeating:0,count:65535)); try b.append(Data([1])); let bounded=try b.finish(); precondition(bounded.count==65536)
do {try b.append(Data([2])); fatalError("cap ignored")} catch ReceiverCoveragePreflight.BoundaryError.invalidResponse {}
do {_ = try b.finish(); fatalError("partial evidence exposed")} catch ReceiverCoveragePreflight.BoundaryError.invalidResponse {}
do {try b.append(Data()); fatalError("poison cleared")} catch ReceiverCoveragePreflight.BoundaryError.invalidResponse {}
print("buffer\\tok")
''')
    return '\n'.join(lines)


@unittest.skipUnless(os.environ.get('HEALTHMD_TEST_NATIVE_BOUNDARY') == '1', 'explicit host native diagnostic')
class NativeBoundaryTests(unittest.TestCase):
    def run_command(self, command):
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def verify_output(self, output):
        actual = dict(line.split('\t', 1) for line in output.strip().splitlines())
        for name, config, accepted in configurations():
            self.assertEqual(actual.pop(name), expected_binding(config) if accepted else 'invalid', name)
        for name, dates, accepted, end in OCCURRENCES:
            value = actual.pop('occ_' + name)
            if not accepted:
                self.assertEqual(value, 'invalid', name)
            else:
                self.assertEqual(json.loads(base64.b64decode(value)), dict(schema='healthmd.receiver_coverage.request',
                    schema_version=1, request_id='occurrence-1', scope_id=BASE['scope'],
                    calendar_timezone=BASE['zone'], start=dates[0], end_exclusive=end), name)
        utc_body = json.loads(base64.b64decode(actual.pop('utc_body')))
        self.assertEqual(utc_body['calendar_timezone'], 'UTC')
        self.assertEqual(utc_body['end_exclusive'], '2026-03-09')
        self.assertEqual(actual, {'buffer': 'ok'})

    def test_swift(self):
        if not shutil.which('swiftc'):
            self.skipTest('Swift compiler unavailable')
        with tempfile.TemporaryDirectory(prefix='healthmd-170-swift-') as tmp:
            directory = Path(tmp)
            main = directory / 'main.swift'
            main.write_text(harness())
            binary = directory / 'tests'
            self.run_command(['swiftc', '-swift-version', '6', '-module-cache-path', str(directory / 'modules'),
                              str(SWIFT), str(main), '-o', str(binary)])
            self.verify_output(self.run_command([str(binary)]))

    def test_kotlin(self):
        compiler = os.environ.get('HEALTHMD_KOTLIN_COMPILER_CLASSPATH')
        stdlib = os.environ.get('HEALTHMD_KOTLIN_STDLIB')
        if compiler and stdlib:
            command = ['java', '-cp', compiler, 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                       '-no-stdlib', '-no-reflect', '-classpath', stdlib]
        elif shutil.which('kotlinc') and shutil.which('kotlin'):
            command = ['kotlinc']
        else:
            self.skipTest('Kotlin compiler unavailable')
        with tempfile.TemporaryDirectory(prefix='healthmd-170-kotlin-') as tmp:
            directory = Path(tmp)
            main = directory / 'Main.kt'
            main.write_text(harness(True))
            jar = directory / 'tests.jar'
            self.run_command(command + [str(KOTLIN), str(main), '-d', str(jar)])
            runner = ['java', '-cp', str(jar) + os.pathsep + stdlib, 'MainKt'] if compiler and stdlib else ['kotlin', '-classpath', str(jar), 'MainKt']
            self.verify_output(self.run_command(runner))


if __name__ == '__main__':
    unittest.main()
