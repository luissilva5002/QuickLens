window.embeddingModel = null;
window.isModelLoading = false; // Add a lock

async function loadTFLiteModel(unusedBytes) {
    if (window.embeddingModel) return true;
    if (window.isModelLoading) return false; // Prevent double loading

    window.isModelLoading = true;

    const pathPrefix = window.location.origin + window.location.pathname;

    // 1. Try strict path (Flutter Web default)
    // Most likely path: assets/assets/all-MiniLM-L6-v2-quant.tflite
    let modelPath = pathPrefix + "assets/assets/all-MiniLM-L6-v2-quant.tflite";

    try {
        console.log("Trying path 1:", modelPath);
        window.embeddingModel = await tf.tflite.loadTFLiteModel(modelPath);
        console.log("✅ Model loaded!");
        window.isModelLoading = false;
        return true;
    } catch (e) {
        console.warn("Path 1 failed:", e);

        // 2. Try fallback path (assets/...)
        try {
            modelPath = pathPrefix + "assets/all-MiniLM-L6-v2-quant.tflite";
            console.log("Trying path 2:", modelPath);
            window.embeddingModel = await tf.tflite.loadTFLiteModel(modelPath);
            console.log("✅ Model loaded (Fallback)!");
            window.isModelLoading = false;
            return true;
        } catch (e2) {
            console.error("❌ ALL LOAD ATTEMPTS FAILED.");
            window.isModelLoading = false;
            return false;
        }
    }
}
async function runPrediction(inputIds, attentionMask, tokenTypeIds, maxSequenceLength) {
    if (!window.embeddingModel) {
        throw new Error("Model is not loaded.");
    }

    try {
        // TFLite requires explicit shape
        const shape = [1, maxSequenceLength];

        // FIX: BERT Inputs MUST be 'int32'.
        // Even though Dart sent Float32List, we tell TF.js to treat them as int32.
        const inputTensor = tf.tensor(inputIds, shape, 'int32');
        const maskTensor = tf.tensor(attentionMask, shape, 'int32');
        const tokenTensor = tf.tensor(tokenTypeIds, shape, 'int32');

        // Prepare inputs array (Order matters: ids, mask, types)
        const inputs = [inputTensor, maskTensor, tokenTensor];

        // Run Inference
        const output = await window.embeddingModel.predict(inputs);

        // Handle Output
        let outputTensor = output;
        if (Array.isArray(output)) outputTensor = output[0]; // Take first output

        // Convert back to data
        const outputData = await outputTensor.data();

        // Cleanup memory
        inputTensor.dispose();
        maskTensor.dispose();
        tokenTensor.dispose();
        outputTensor.dispose();

        return outputData;

    } catch (e) {
        console.error("Prediction Error:", e);
        throw e;
    }
}

// Expose to Dart
window.loadEmbeddingModel = async function(modelBytes) {
    try {
        await loadTFLiteModel(modelBytes);
        return true; // Return success boolean to Dart
    } catch (e) {
        return false;
    }
}

window.vectorizeText = runPrediction;