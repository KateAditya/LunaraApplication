export const getImageUrl = (filePath?: string | any): string => {
    if (!filePath) return '';
    if (typeof filePath !== 'string') return '';
    
    let clean = filePath.replace(/\\/g, '/').trim();
    if (!clean) return '';

    // Fix malformed URLs missing colon e.g. https// -> https:// or http// -> http://
    if (clean.startsWith('https//')) {
        clean = clean.replace('https//', 'https://');
    } else if (clean.startsWith('http//')) {
        clean = clean.replace('http//', 'http://');
    }

    // Check if the path is already a full absolute URL or Azure Blob URL
    if (
        clean.startsWith('http://') ||
        clean.startsWith('https://') ||
        clean.includes('.blob.core.windows.net') ||
        clean.includes('://')
    ) {
        return clean;
    }

    const baseUrl = import.meta.env.VITE_API_URL || 'http://localhost:5000';
    const formattedPath = clean.startsWith('/') ? clean : '/' + clean;
    return `${baseUrl}${formattedPath}`;
};
