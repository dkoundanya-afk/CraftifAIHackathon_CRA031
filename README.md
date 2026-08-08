## What I Built
A real-time edge AI perception pipeline using PipeGen that performs live human pose estimation and detects when a person raises both hands above their head, triggering an on-screen alert and logging the event to a JSON file.

## Pipeline
- **Input**: Video file 
- **Model**: Pose estimation (ONNX, compiled to TensorRT FP32)
- **Postprocess**: Custom raised-hands event detection from skeleton keypoints
- **Outputs**: Live display with skeleton overlay + JSON event log

## Results
- 459 frames processed
- Full skeleton tracking with 17-keypoint COCO format
- mIoU 0.9986 accuracy vs. original ONNX model
- Clean pipeline completion (EOS after 15.29s)

## How to Run
[Add your run.vms.sh command / instructions here]
