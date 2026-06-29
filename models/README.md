Upscale models used by the project.

Prefer ONNX/NCNN over PyTorch since chaiNNer doesn't support AMD GPU acceleration for PyTorch on Windows.

Upscale models needed by the project are defined in `upscale-models.json`. `ModelName` is used as the models filename, and `Mirrors` contains the url(s) where the model can be downloaded when running `get-upscale-models.ps1`. `HashSHA1` is the SHA1 hash of the model file, used to verify it's contents after downloading (obtain using `Get-FileHash <model-file> -Algorithm SHA1`)

More upscale models can be found at https://openmodeldb.info/

# Attributions

"[PBRify_UpscalerV4](https://github.com/Kim2091/Kim2091-Models/releases/tag/4x-PBRify_UpscalerV4)" by [Kim2091](https://github.com/Kim2091) is licensed under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (Converted to ONNX format by [mikebm94](https://github.com/mikebm94))
