import React, { useState, useCallback } from 'react';
import Cropper from 'react-easy-crop';
import { BiX, BiCheck, BiReset } from 'react-icons/bi';
import { MdRotate90DegreesCcw } from 'react-icons/md';

interface ImageCropModalProps {
    imageSrc: string;
    onCropComplete: (croppedImage: File) => void;
    onCancel: () => void;
    aspectRatio?: number;
    cropShape?: 'rect' | 'round';
}

interface AspectRatioPreset {
    label: string;
    value: number;
}

const ASPECT_RATIO_PRESETS: AspectRatioPreset[] = [
    { label: '16:9 (Recommended)', value: 16 / 9 },
    { label: '1:1 (Square)', value: 1 },
    { label: '4:3', value: 4 / 3 },
    { label: '3:2', value: 3 / 2 },
    { label: 'Free', value: 0 },
];

const overlay: React.CSSProperties = {
    position: 'fixed',
    inset: 0,
    background: 'rgba(0,0,0,0.8)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 1090,
    backdropFilter: 'blur(4px)',
};

const modalContainer: React.CSSProperties = {
    width: '100%',
    maxWidth: 900,
    maxHeight: '95vh',
    background: 'var(--vz-card-bg)',
    borderRadius: 'var(--vz-radius-lg)',
    overflow: 'hidden',
    boxShadow: '0 10px 50px rgba(0,0,0,0.3)',
    display: 'flex',
    flexDirection: 'column',
};

const headerStyle: React.CSSProperties = {
    padding: '1rem 1.25rem',
    borderBottom: '1px solid var(--vz-border-color)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
};

const cropContainerStyle: React.CSSProperties = {
    position: 'relative',
    width: '100%',
    height: 500,
    background: '#000',
    flex: 1,
};

const sidebarStyle: React.CSSProperties = {
    width: 280,
    borderLeft: '1px solid var(--vz-border-color)',
    overflowY: 'auto',
    padding: '1rem',
    background: 'var(--vz-body-bg)',
};

const footerStyle: React.CSSProperties = {
    padding: '0.875rem 1.25rem',
    borderTop: '1px solid var(--vz-border-color)',
    display: 'flex',
    justifyContent: 'flex-end',
    gap: '0.5rem',
    background: 'var(--vz-card-bg)',
};

const controlSectionStyle: React.CSSProperties = {
    marginBottom: '1.25rem',
};

const sectionTitleStyle: React.CSSProperties = {
    fontSize: '0.75rem',
    fontWeight: 700,
    color: 'var(--vz-text-secondary)',
    marginBottom: '0.625rem',
    textTransform: 'uppercase',
    letterSpacing: '0.04em',
};

const buttonStyle = (active: boolean = false): React.CSSProperties => ({
    width: '100%',
    padding: '0.5rem 0.75rem',
    borderRadius: 'var(--vz-radius)',
    border: `1.5px solid ${active ? 'var(--vz-primary)' : 'var(--vz-border-color)'}`,
    background: active ? 'rgba(var(--vz-primary-rgb), 0.1)' : 'transparent',
    color: active ? 'var(--vz-primary)' : 'var(--vz-text-secondary)',
    fontSize: '0.8125rem',
    fontWeight: active ? 600 : 400,
    cursor: 'pointer',
    transition: 'all 0.2s ease',
    marginBottom: '0.375rem',
    textAlign: 'left',
    display: 'flex',
    alignItems: 'center',
    gap: '0.5rem',
});

const sliderContainerStyle: React.CSSProperties = {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.5rem',
};

const sliderLabelStyle: React.CSSProperties = {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    fontSize: '0.75rem',
    fontWeight: 500,
};

export const ImageCropModal: React.FC<ImageCropModalProps> = ({
    imageSrc,
    onCropComplete,
    onCancel,
    aspectRatio = 16 / 9,
    cropShape = 'rect',
}) => {
    const [crop, setCrop] = useState({ x: 0, y: 0 });
    const [zoom, setZoom] = useState(1);
    const [rotation, setRotation] = useState(0);
    const [brightness, setBrightness] = useState(100);
    const [contrast, setContrast] = useState(100);
    const [flipH, setFlipH] = useState(false);
    const [flipV, setFlipV] = useState(false);
    const [currentAspectRatio, setCurrentAspectRatio] = useState(aspectRatio);
    const [croppedAreaPixels, setCroppedAreaPixels] = useState<any>(null);
    const [isProcessing, setIsProcessing] = useState(false);

    const handleCropAreaChange = useCallback(
        (_croppedArea: any, croppedAreaPixels: any) => {
            setCroppedAreaPixels(croppedAreaPixels);
        },
        []
    );

    const handleReset = () => {
        setCrop({ x: 0, y: 0 });
        setZoom(1);
        setRotation(0);
        setBrightness(100);
        setContrast(100);
        setFlipH(false);
        setFlipV(false);
        setCurrentAspectRatio(aspectRatio);
    };

    const handleConfirm = async () => {
        if (!croppedAreaPixels) return;

        setIsProcessing(true);
        try {
            const img = new Image();
            img.src = imageSrc;

            img.onload = () => {
                // Create intermediate canvas for transformations
                const tempCanvas = document.createElement('canvas');
                const { width, height, x, y } = croppedAreaPixels;

                tempCanvas.width = width;
                tempCanvas.height = height;

                const tempCtx = tempCanvas.getContext('2d', { willReadFrequently: true });
                if (!tempCtx) {
                    setIsProcessing(false);
                    return;
                }

                // First, crop the image
                tempCtx.drawImage(img, x, y, width, height, 0, 0, width, height);

                // Create final canvas with transformations
                const canvas = document.createElement('canvas');
                
                // Calculate new dimensions considering rotation
                const hasRotation = rotation % 180 !== 0;
                if (hasRotation && (rotation % 90 === 0)) {
                    if (rotation === 90 || rotation === 270) {
                        canvas.width = height;
                        canvas.height = width;
                    } else {
                        canvas.width = width;
                        canvas.height = height;
                    }
                } else {
                    canvas.width = width;
                    canvas.height = height;
                }

                const ctx = canvas.getContext('2d', { willReadFrequently: true });
                if (!ctx) {
                    setIsProcessing(false);
                    return;
                }

                // Apply brightness and contrast via filter
                ctx.filter = `brightness(${brightness}%) contrast(${contrast}%)`;

                // Save context state
                ctx.save();

                // Move to center for rotation
                ctx.translate(canvas.width / 2, canvas.height / 2);

                // Apply rotation
                if (rotation > 0) {
                    ctx.rotate((rotation * Math.PI) / 180);
                }

                // Apply flips (scale)
                let scaleX = flipH ? -1 : 1;
                let scaleY = flipV ? -1 : 1;
                ctx.scale(scaleX, scaleY);

                // Draw the cropped image centered
                ctx.drawImage(tempCanvas, -width / 2, -height / 2, width, height);

                // Restore context
                ctx.restore();

                // Convert to blob and create file
                canvas.toBlob(
                    (blob) => {
                        if (blob) {
                            const file = new File([blob], 'cropped-cover-image.jpg', {
                                type: 'image/jpeg',
                            });
                            onCropComplete(file);
                        }
                        setIsProcessing(false);
                    },
                    'image/jpeg',
                    0.95
                );
            };

            img.onerror = () => {
                console.error('Failed to load image');
                setIsProcessing(false);
            };
        } catch (error) {
            console.error('Error cropping image:', error);
            setIsProcessing(false);
        }
    };

    return (
        <div style={overlay} onClick={onCancel}>
            <div style={modalContainer} onClick={(e) => e.stopPropagation()}>
                {/* Header */}
                <div style={headerStyle}>
                    <h6 style={{ margin: 0, fontSize: '1rem', fontWeight: 600 }}>
                        Advanced Image Cropper
                    </h6>
                    <button
                        onClick={onCancel}
                        style={{
                            background: 'none',
                            border: 'none',
                            fontSize: '1.25rem',
                            cursor: 'pointer',
                            color: 'var(--vz-text-primary)',
                            display: 'flex',
                            alignItems: 'center',
                        }}
                    >
                        <BiX />
                    </button>
                </div>

                {/* Main Content */}
                <div style={{ display: 'flex', flex: 1, minHeight: 0 }}>
                    {/* Crop Area */}
                    <div style={{ ...cropContainerStyle, flex: 1 }}>
                        <Cropper
                            image={imageSrc}
                            crop={crop}
                            zoom={zoom}
                            aspect={currentAspectRatio === 0 ? undefined : currentAspectRatio}
                            cropShape={cropShape}
                            showGrid={true}
                            onCropChange={setCrop}
                            onCropAreaChange={handleCropAreaChange}
                            onZoomChange={setZoom}
                        />
                    </div>

                    {/* Sidebar Controls */}
                    <div style={sidebarStyle}>
                        {/* Transformation Preview */}
                        <div style={controlSectionStyle}>
                            <div style={sectionTitleStyle}>Preview</div>
                            <div
                                style={{
                                    width: '100%',
                                    aspectRatio: currentAspectRatio === 0 ? '1 / 1' : `${currentAspectRatio} / 1`,
                                    borderRadius: 'var(--vz-radius)',
                                    overflow: 'hidden',
                                    background: '#f8f9fa',
                                    border: '1px solid var(--vz-border-color)',
                                    marginBottom: '0.75rem',
                                    display: 'flex',
                                    alignItems: 'center',
                                    justifyContent: 'center',
                                    minHeight: 120,
                                }}
                            >
                                <div
                                    style={{
                                        position: 'relative',
                                        width: '90%',
                                        height: '90%',
                                        overflow: 'hidden',
                                    }}
                                >
                                    <img
                                        src={imageSrc}
                                        alt="Preview"
                                        style={{
                                            width: '100%',
                                            height: '100%',
                                            objectFit: 'cover',
                                            filter: `brightness(${brightness}%) contrast(${contrast}%)`,
                                            transform: `rotate(${rotation}deg) scaleX(${flipH ? -1 : 1}) scaleY(${flipV ? -1 : 1})`,
                                            transformOrigin: 'center',
                                        }}
                                    />
                                </div>
                            </div>
                        </div>

                        {/* Aspect Ratio */}
                        <div style={controlSectionStyle}>
                            <div style={sectionTitleStyle}>Aspect Ratio</div>
                            {ASPECT_RATIO_PRESETS.map((preset) => (
                                <button
                                    key={preset.label}
                                    onClick={() => setCurrentAspectRatio(preset.value)}
                                    style={buttonStyle(currentAspectRatio === preset.value)}
                                >
                                    {preset.label}
                                </button>
                            ))}
                        </div>

                        {/* Zoom */}
                        <div style={controlSectionStyle}>
                            <div style={sectionTitleStyle}>Zoom</div>
                            <div style={sliderContainerStyle}>
                                <div style={sliderLabelStyle}>
                                    <span>Zoom Level</span>
                                    <span style={{ color: 'var(--vz-primary)', fontWeight: 600 }}>
                                        {(zoom * 100).toFixed(0)}%
                                    </span>
                                </div>
                                <input
                                    type="range"
                                    min="1"
                                    max="3"
                                    step="0.1"
                                    value={zoom}
                                    onChange={(e) => setZoom(Number(e.target.value))}
                                    style={{
                                        width: '100%',
                                        cursor: 'pointer',
                                        accentColor: 'var(--vz-primary)',
                                    }}
                                />
                            </div>
                        </div>

                        {/* Rotation */}
                        <div style={controlSectionStyle}>
                            <div style={sectionTitleStyle}>Rotation</div>
                            <div style={sliderContainerStyle}>
                                <div style={sliderLabelStyle}>
                                    <span>Angle</span>
                                    <span style={{ color: 'var(--vz-primary)', fontWeight: 600 }}>
                                        {rotation}°
                                    </span>
                                </div>
                                <input
                                    type="range"
                                    min="0"
                                    max="360"
                                    step="5"
                                    value={rotation}
                                    onChange={(e) => setRotation(Number(e.target.value))}
                                    style={{
                                        width: '100%',
                                        cursor: 'pointer',
                                        accentColor: 'var(--vz-primary)',
                                    }}
                                />
                                <button
                                    onClick={() => setRotation((prev) => (prev + 90) % 360)}
                                    style={{
                                        ...buttonStyle(false),
                                        marginBottom: 0,
                                        background: 'rgba(var(--vz-primary-rgb), 0.1)',
                                        color: 'var(--vz-primary)',
                                    }}
                                >
                                    <MdRotate90DegreesCcw /> Rotate 90°
                                </button>
                            </div>
                        </div>

                        {/* Brightness & Contrast */}
                        <div style={controlSectionStyle}>
                            <div style={sectionTitleStyle}>Adjustments</div>
                            <div style={sliderContainerStyle}>
                                <div style={sliderLabelStyle}>
                                    <span>Brightness</span>
                                    <span style={{ color: 'var(--vz-success)', fontWeight: 600 }}>
                                        {brightness}%
                                    </span>
                                </div>
                                <input
                                    type="range"
                                    min="50"
                                    max="150"
                                    step="5"
                                    value={brightness}
                                    onChange={(e) => setBrightness(Number(e.target.value))}
                                    style={{
                                        width: '100%',
                                        cursor: 'pointer',
                                        accentColor: 'var(--vz-success)',
                                    }}
                                />
                                <div style={sliderLabelStyle}>
                                    <span>Contrast</span>
                                    <span style={{ color: 'var(--vz-success)', fontWeight: 600 }}>
                                        {contrast}%
                                    </span>
                                </div>
                                <input
                                    type="range"
                                    min="50"
                                    max="150"
                                    step="5"
                                    value={contrast}
                                    onChange={(e) => setContrast(Number(e.target.value))}
                                    style={{
                                        width: '100%',
                                        cursor: 'pointer',
                                        accentColor: 'var(--vz-success)',
                                    }}
                                />
                            </div>
                        </div>

                        {/* Flip */}
                        <div style={controlSectionStyle}>
                            <div style={sectionTitleStyle}>Flip</div>
                            <button
                                onClick={() => setFlipH(!flipH)}
                                style={buttonStyle(flipH)}
                            >
                                {flipH ? '✓' : ''} Flip Horizontal
                            </button>
                            <button
                                onClick={() => setFlipV(!flipV)}
                                style={buttonStyle(flipV)}
                            >
                                {flipV ? '✓' : ''} Flip Vertical
                            </button>
                        </div>

                        {/* Reset */}
                        <div style={controlSectionStyle}>
                            <button
                                onClick={handleReset}
                                style={{
                                    ...buttonStyle(false),
                                    marginBottom: 0,
                                    background: 'rgba(var(--vz-warning-rgb), 0.1)',
                                    color: 'var(--vz-warning)',
                                    borderColor: 'var(--vz-warning)',
                                }}
                            >
                                <BiReset /> Reset All
                            </button>
                        </div>
                    </div>
                </div>

                {/* Footer */}
                <div style={footerStyle}>
                    <button
                        onClick={onCancel}
                        style={{
                            padding: '0.625rem 1rem',
                            borderRadius: 'var(--vz-radius)',
                            border: '1px solid var(--vz-border-color)',
                            background: 'var(--vz-light)',
                            color: 'var(--vz-text-primary)',
                            fontSize: '0.875rem',
                            fontWeight: 600,
                            cursor: 'pointer',
                            transition: 'all 0.2s ease',
                            display: 'flex',
                            alignItems: 'center',
                            gap: '0.375rem',
                        }}
                        disabled={isProcessing}
                    >
                        <BiX /> Cancel
                    </button>
                    <button
                        onClick={handleConfirm}
                        style={{
                            padding: '0.625rem 1rem',
                            borderRadius: 'var(--vz-radius)',
                            border: 'none',
                            background: 'var(--vz-primary)',
                            color: '#fff',
                            fontSize: '0.875rem',
                            fontWeight: 600,
                            cursor: 'pointer',
                            transition: 'all 0.2s ease',
                            display: 'flex',
                            alignItems: 'center',
                            gap: '0.375rem',
                        }}
                        disabled={isProcessing}
                    >
                        <BiCheck /> {isProcessing ? 'Processing...' : 'Apply & Upload'}
                    </button>
                </div>
            </div>
        </div>
    );
};
