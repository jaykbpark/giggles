import torch
import clip
import numpy as np
from PIL import Image
from typing import List, Union, Optional
from io import BytesIO
import base64


class Vectorizer:
    def __init__(self, model_name: str = "ViT-B/32", device: Optional[str] = None):
        self.device = device or ("cuda" if torch.cuda.is_available() else "cpu")
        self.model, self.preprocess = clip.load(model_name, device=self.device)
        self.model.eval()
        self.embedding_dim = 512
        
    @staticmethod
    def available_models() -> List[str]:
        return clip.available_models()
    
    def encode_image(self, image: Union[Image.Image, bytes, str]) -> np.ndarray:
        if isinstance(image, bytes):
            image = Image.open(BytesIO(image)).convert("RGB")
        elif isinstance(image, str):
            image_bytes = base64.b64decode(image)
            image = Image.open(BytesIO(image_bytes)).convert("RGB")
        elif isinstance(image, Image.Image):
            image = image.convert("RGB")
        else:
            raise ValueError(f"Unsupported image type: {type(image)}")
        
        image_input = self.preprocess(image).unsqueeze(0).to(self.device)
        
        with torch.no_grad():
            image_features = self.model.encode_image(image_input)
            image_features = image_features / image_features.norm(dim=-1, keepdim=True)
            
        return image_features.cpu().numpy().flatten()
    
    def encode_images(self, images):
        if not images:
            return np.empty((0, 512), dtype=np.float32)

        processed_images = []

        for img in images:
            if isinstance(img, np.ndarray):
                pil_img = Image.fromarray(img).convert("RGB")
            elif isinstance(img, bytes):
                pil_img = Image.open(BytesIO(img)).convert("RGB")
            elif isinstance(img, str):
                pil_img = Image.open(BytesIO(base64.b64decode(img))).convert("RGB")
            elif isinstance(img, Image.Image):
                pil_img = img.convert("RGB")
            else:
                raise ValueError(f"Unsupported image type: {type(img)}")

            processed_images.append(self.preprocess(pil_img))

        image_batch = torch.stack(processed_images).to(self.device)

        with torch.no_grad():
            image_features = self.model.encode_image(image_batch)
            image_features = image_features / image_features.norm(dim=-1, keepdim=True)

        return image_features.cpu().numpy().astype(np.float32)

    
    def encode_text(self, text: Union[str, List[str]]) -> np.ndarray:
        if isinstance(text, str):
            text = [text]
        
        truncated_texts = []
        for t in text:
            truncated_texts.append(t[:300] if len(t) > 300 else t)
        
        text_tokens = clip.tokenize(truncated_texts, truncate=True).to(self.device)
        
        with torch.no_grad():
            text_features = self.model.encode_text(text_tokens)
            text_features = text_features / text_features.norm(dim=-1, keepdim=True)
        
        result = text_features.cpu().numpy()
        return result.flatten() if len(text) == 1 else result


_vectorizer_instance: Optional[Vectorizer] = None


def get_vectorizer(model_name: str = "ViT-B/32") -> Vectorizer:
    global _vectorizer_instance
    if _vectorizer_instance is None:
        _vectorizer_instance = Vectorizer(model_name=model_name)
    return _vectorizer_instance


def vectorize_frames(frames: List[Union[Image.Image, bytes, str]]) -> np.ndarray:
    vectorizer = get_vectorizer()
    return vectorizer.encode_images(frames)


def vectorize_text(text: str) -> np.ndarray:
    vectorizer = get_vectorizer()
    return vectorizer.encode_text(text)


if __name__ == "__main__":
    print("Available CLIP models:", clip.available_models())
    
    v = Vectorizer()
    print(f"Using device: {v.device}")
    print(f"Embedding dimension: {v.embedding_dim}")
    
    test_text = "A person talking about artificial intelligence"
    text_vector = v.encode_text(test_text)
    print(f"Text embedding shape: {text_vector.shape}")
    print(f"Text embedding norm: {np.linalg.norm(text_vector):.4f}")
