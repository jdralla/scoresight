import os
import platform
from camera_info import CameraInfo
from sc_logging import logger
from storage import fetch_data

# This file contains the code to get the camera information for the current OS


def get_camera_info_windows():
    from win32DeviceEnum import enum_devices_dshow

    device_info = []
    cameras = enum_devices_dshow.enumerate_video_devices_dshow()
    for camera in cameras:
        device_info.append(
            CameraInfo(
                camera[1], str(camera[0]), camera[0], CameraInfo.CameraType.OPENCV
            )
        )

    return device_info


def get_camera_info_mac():
    import AVFoundation as AV

    device_info = []
    devices = AV.AVCaptureDevice.devicesWithMediaType_(AV.AVMediaTypeVideo)

    for i, device in enumerate(devices):
        device_info.append(
            CameraInfo(
                device.localizedName(),
                device.uniqueID(),
                i,
                CameraInfo.CameraType.OPENCV,
            )
        )

    # sort by the ID, since opencv sorts by ID
    device_info.sort(key=lambda x: x.uuid)
    # update the ID
    for i, camera in enumerate(device_info):
        camera.id = i

    return device_info


def get_camera_info_linux():
    # Basic method using /dev/video* enumeration
    import glob

    device_info = glob.glob("/dev/video*")
    device_info = [
        CameraInfo(f"Camera {i}", dev, i, CameraInfo.CameraType.OPENCV)
        for i, dev in enumerate(device_info)
    ]
    return device_info


def ndi_enabled() -> bool:
    if os.getenv("SCORESIGHT_DISABLE_NDI"):
        return False
    return bool(fetch_data("scoresight.json", "enable_ndi", True))


def get_camera_info() -> list[CameraInfo]:
    logger.info("Getting cameras info")
    os_name = platform.system()
    cameras = []
    if os_name == "Windows":
        cameras += get_camera_info_windows()
    elif os_name == "Darwin":
        cameras += get_camera_info_mac()
    elif os_name == "Linux":
        cameras += get_camera_info_linux()

    # Add NDI cameras. NDI discovery can be turned off with "enable_ndi": false
    # in scoresight.json or SCORESIGHT_DISABLE_NDI=1, which also avoids loading
    # the NDI runtime at all.
    if ndi_enabled():
        try:
            from ndi import NDICapture

            cameras += NDICapture.get_camera_info_ndi()
        except Exception as e:
            logger.error(f"Could not enumerate NDI sources: {e}")
    else:
        logger.info("NDI discovery disabled")

    return cameras
