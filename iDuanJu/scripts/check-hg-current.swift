// Standalone macOS regression runner: compile with the production signing sources.
import Foundation
import CryptoKit

@main struct CheckHGCurrent {
    static func main() throws {
        let base=URL(fileURLWithPath:CommandLine.arguments[1])
        func data(_ name:String)throws->Data {try Data(contentsOf:base.appendingPathComponent(name))}
        func sha(_ b:[UInt8])->String {SHA256.hash(data:Data(b)).map{String(format:"%02x",$0)}.joined()}
        struct Input:Decodable {
            var raw_query:String,record_digest:Data,factor_pb:Data,material:Data,license_id:String,aid:String
            var seconds:UInt64,gorgon_nonce:UInt16,native_gorgon_flags:UInt16,helios_random:UInt32,medusa_random1:UInt32,medusa_random2:UInt32,local_buffer_address:UInt64,previous_thread_state:UInt32
        }
        struct Whole:Decodable {var id:String,inputs:Input,expected_header_sha256:[String:String],expected_thread_state:UInt32}
        struct Transform:Decodable {var branch:Int,key:Data,iv:Data,plain:Data,expected_sha256:String}
        struct Fixture:Decodable {var synthetic_only:Bool,whole:[Whole],transforms:[Transform]}
        struct Factor:Decodable {var toy_seed:Int,public_input_seed:Int,public_seconds:UInt32,output_sha256:String}
        let fixture=try JSONDecoder().decode(Fixture.self,from:data("current_crypto.json"))
        guard fixture.synthetic_only,fixture.whole.count==32,fixture.transforms.count==22 else {throw ProviderError.invalid("fixture")}
        for v in fixture.whole {
            let x=v.inputs
            let got=try HGCurrentPlayer.compute(query:x.raw_query,digest:Array(x.record_digest),pb:Array(x.factor_pb),material:Array(x.material),license:x.license_id,aid:x.aid,seconds:x.seconds,nonce:x.gorgon_nonce,flags:x.native_gorgon_flags,heliosRandom:x.helios_random,random1:x.medusa_random1,random2:x.medusa_random2,local:x.local_buffer_address,previous:x.previous_thread_state)
            guard got.state==v.expected_thread_state else {throw ProviderError.invalid("state \(v.id)")}
            for (k,expected) in v.expected_header_sha256 {guard sha(Array((got.headers[k] ?? "").utf8))==expected else {throw ProviderError.invalid("\(v.id) \(k)")}}
        }
        for v in fixture.transforms {guard sha(try HGCurrentPlayer.transform(Array(v.plain),Array(v.key),Array(v.iv),v.branch))==v.expected_sha256 else {throw ProviderError.invalid("transform")}}
        let factors=try JSONDecoder().decode([Factor].self,from:data("current_factor.json"));guard factors.count==48 else {throw ProviderError.invalid("factors")}
        for f in factors {let input=(0..<52).map{UInt8(truncatingIfNeeded:$0*37+f.public_input_seed)};guard sha(try HGCurrentPlayer.factor(input,f.public_seconds,f.toy_seed))==f.output_sha256 else {throw ProviderError.invalid("factor")}}
        let pairs=[("aid","8662"),("device_id","1000000000000000001"),("version_name","7.3.9.32"),("ts","old"),("_rticket","old")]
        var crossed=false
        for i in 0..<32 {
            let now:Int64=1794827000999+Int64(i)*1000
            let result=try HGCurrentPlayer.sign(pairs:pairs,nowMillis:now,deviceID:pairs[1].1,versionName:pairs[2].1,body:Array(#"{"video_id":"synthetic-1"}"#.utf8),entropy:(0..<24).map{UInt8($0<20 ? $0+1:0)})
            guard let ticket=Int64(result.headers["x-ss-req-ticket"] ?? ""),ticket>=now,ticket<now+128,result.headers["x-khronos"]==String(ticket/1000) else {throw ProviderError.invalid("ticket")}
            crossed=crossed || ticket/1000 != now/1000
        }
        guard crossed else {throw ProviderError.invalid("boundary not exercised")}
        let category = try HGPlayerSign.playbackHeaders(query: "aid=8662&device_id=12345&version_name=7.3.9.32&ts=1700000000&_rticket=1700000000123", body: Array(#"{"video_id":"42"}"#.utf8), timestamp: 1700000000, argusRandom: 123456789, ladonRandom: 0x4e38220c, emptyInstallToken: true)
        guard category["x-argus"] == "8oHyrVYEy1xDCDlx64ko40qC6JC9VYY/ZkjJzEl50iSFDw8Yfph1hupLxfKrA9GswSEz0Yi4goA7OQ4u+H8ECdOaQhJiO70jsz7mX7TvvtFfiAeLdglueZk1gtRL/PIXBma+d3IKI3d6CMG/O0CHHhYGEN4hmhz6tNG42M8oJZQUx/Dw6jRGZk1wXUyDFqKe6V09LQh5y7Thf3GWO4RIgXDv5uPtCbhHbwn9PZY2VPuRMUAbogfTJ9Ijp7Pu6XCP5EQR5nI2JTK8A9b7RGYIfIeQ", category["x-ladon"] == "DCI4TntjztbzoPWZ0NBDr7CfcwXQTs2iMUwCwlyNrCS8bqTW" else { throw ProviderError.invalid("category 551 vector") }
        print("PASS: 32 native envelopes, 22 transforms, 48 factors and 32 request time bindings")
    }
}
