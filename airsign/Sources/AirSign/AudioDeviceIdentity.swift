import CoreAudio
import Foundation

public enum AudioDeviceIdentity {
    public static func currentOutput() -> (uid: String, name: String)? {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultOutputDeviceID
        )
        guard status == noErr, defaultOutputDeviceID != kAudioObjectUnknown else {
            return nil
        }

        // 1. Device UID
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedUID: Unmanaged<CFString>? = nil
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let uidStatus = withUnsafeMutablePointer(to: &unmanagedUID) { ptr in
            AudioObjectGetPropertyData(
                defaultOutputDeviceID,
                &uidAddress,
                0,
                nil,
                &uidSize,
                ptr
            )
        }
        guard uidStatus == noErr, let unmanagedUID = unmanagedUID else {
            return nil
        }
        let uid = unmanagedUID.takeRetainedValue() as String

        // 2. Device Name
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>? = nil
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let nameStatus = withUnsafeMutablePointer(to: &unmanagedName) { ptr in
            AudioObjectGetPropertyData(
                defaultOutputDeviceID,
                &nameAddress,
                0,
                nil,
                &nameSize,
                ptr
            )
        }
        let name: String
        if nameStatus == noErr, let unmanagedName = unmanagedName {
            name = unmanagedName.takeRetainedValue() as String
        } else {
            name = ""
        }

        return (uid: uid, name: name)
    }
}
