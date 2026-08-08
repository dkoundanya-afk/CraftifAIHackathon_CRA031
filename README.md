# CraftifAI Hackathon — Live Human Pose Estimation Pipeline

## Overview
A real-time AI perception pipeline built with PipeGen that performs live human pose estimation. Operating entirely locally, it cleanly tracks a human subject across a video feed, accurately extracting and mapping 17 essential body keypoints without any tracking drop-offs. 

## Real-World Applications
Because this pipeline reliably tracks full-body keypoints at the edge, it can serve as the foundational tracking layer for several real-world systems:
* **Sports & Fitness Analytics:** Analyzing an athlete's form, posture, and biomechanics during workouts to optimize performance and prevent injury.
* **Physical Therapy Monitoring:** Tracking a patient's range of motion and exercise adherence remotely without needing intrusive cloud-based video streaming.
* **Workplace Ergonomics:** Evaluating posture and movement in industrial or office settings (e.g., safe lifting techniques) to reduce strain and workplace injuries.

## Technical Pipeline
- **Input:** 15-second localized video file 
- **Model:** 17-keypoint human pose estimation (ONNX, compiled to TensorRT FP32 for local edge execution)
- **Outputs:** Live video display with full skeleton overlay + structured JSON event log containing coordinate data

## Performance & Results
- **Seamless Tracking:** Cleanly tracked the human subject across **400+ frames** with zero drop-offs.
- **Accuracy:** Full 17-keypoint COCO format mapping with an mIoU of 0.9986 compared to the original ONNX model.
- **Efficiency:** Clean pipeline completion (EOS) after 15.29s of processing.

## How to Run
1. Clone this repository to your local machine.
2. Open the **PipeGen** application and load this project pipeline.
3. Once the model is successfully compiled, click the **"Run with VMS"** button in the PipeGen interface to launch the pipeline and open the visual console.



## Visual Evidence
*(Check the `/screenshots` and `/results` folders in this repository for the pipeline graph, compile reports, and JSON output logs.)*
