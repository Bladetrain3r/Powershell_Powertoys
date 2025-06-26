#!/usr/bin/env python3
"""
Code Vectorizer - Neural network-based code similarity analysis
Uses AST parsing and code2vec-inspired approaches for better code understanding
"""

import sys
import os
import re
import json
import ast
import hashlib
from collections import defaultdict
from typing import List, Dict, Tuple, Any
import argparse

# These will be installed in venv
import numpy as np
from sklearn.feature_extraction.text import CountVectorizer, TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler
import torch
import torch.nn as nn
import torch.nn.functional as F


class CodeFeatureExtractor:
    """Extract meaningful features from code beyond just text"""
    
    def __init__(self):
        self.feature_dims = 128
        
    def extract_ast_features(self, code: str, lang: str) -> Dict[str, float]:
        """Extract AST-based features for Python code"""
        features = defaultdict(float)
        
        if lang == '.py':
            try:
                tree = ast.parse(code)
                
                # Count different node types
                for node in ast.walk(tree):
                    features[f'ast_{type(node).__name__}'] += 1
                
                # Complexity metrics
                features['max_depth'] = self._get_ast_depth(tree)
                features['num_branches'] = sum(1 for n in ast.walk(tree) 
                                              if isinstance(n, (ast.If, ast.For, ast.While)))
                
            except:
                pass
                
        return dict(features)
    
    def extract_structural_features(self, code: str) -> Dict[str, float]:
        """Extract language-agnostic structural features"""
        lines = code.split('\n')
        
        features = {
            'num_lines': len(lines),
            'avg_line_length': np.mean([len(l) for l in lines]) if lines else 0,
            'max_line_length': max([len(l) for l in lines]) if lines else 0,
            'num_blank_lines': sum(1 for l in lines if not l.strip()),
            'indentation_levels': len(set(len(l) - len(l.lstrip()) for l in lines if l.strip())),
            'num_comments': sum(1 for l in lines if l.strip().startswith(('#', '//', '/*', '*'))),
            'cyclomatic_complexity': self._estimate_complexity(code),
            'unique_tokens': len(set(re.findall(r'\w+', code))),
            'total_tokens': len(re.findall(r'\w+', code)),
        }
        
        # Pattern-based features
        features['num_functions'] = len(re.findall(r'(?:def|function|func)\s+\w+', code))
        features['num_classes'] = len(re.findall(r'(?:class|interface)\s+\w+', code))
        features['num_imports'] = len(re.findall(r'(?:import|require|include|using)\s+', code))
        features['num_loops'] = len(re.findall(r'(?:for|while|foreach)\s*\(', code))
        features['num_conditionals'] = len(re.findall(r'(?:if|else|switch|case)\s*\(', code))
        
        return features
    
    def extract_semantic_features(self, code: str) -> np.ndarray:
        """Extract semantic features using n-gram analysis"""
        # Token n-grams (better than character n-grams for code)
        tokens = re.findall(r'\w+|[^\w\s]', code)
        
        # Create token bigrams and trigrams
        bigrams = [f"{tokens[i]}_{tokens[i+1]}" for i in range(len(tokens)-1)]
        trigrams = [f"{tokens[i]}_{tokens[i+1]}_{tokens[i+2]}" for i in range(len(tokens)-2)]
        
        # Use hashing trick for fixed-size representation
        feature_vector = np.zeros(self.feature_dims)
        
        for gram in bigrams + trigrams:
            idx = int(hashlib.md5(gram.encode()).hexdigest(), 16) % self.feature_dims
            feature_vector[idx] += 1
            
        return feature_vector / (len(bigrams) + len(trigrams) + 1)
    
    def _get_ast_depth(self, node, depth=0):
        """Calculate AST depth"""
        if not hasattr(node, '_fields'):
            return depth
        
        max_depth = depth
        for field, value in ast.iter_fields(node):
            if isinstance(value, list):
                for item in value:
                    if isinstance(item, ast.AST):
                        max_depth = max(max_depth, self._get_ast_depth(item, depth + 1))
            elif isinstance(value, ast.AST):
                max_depth = max(max_depth, self._get_ast_depth(value, depth + 1))
                
        return max_depth
    
    def _estimate_complexity(self, code: str) -> int:
        """Estimate cyclomatic complexity"""
        # Simplified: count decision points
        decision_keywords = ['if', 'elif', 'else', 'for', 'while', 'except', 'case', 'catch']
        complexity = 1  # Base complexity
        
        for keyword in decision_keywords:
            complexity += len(re.findall(rf'\b{keyword}\b', code))
            
        return complexity


class CodeSimilarityNet(nn.Module):
    """Neural network for learning code embeddings"""
    
    def __init__(self, input_dim, hidden_dim=256, embedding_dim=64):
        super().__init__()
        
        # Encoder
        self.encoder = nn.Sequential(
            nn.Linear(input_dim, hidden_dim),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(hidden_dim, hidden_dim // 2),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(hidden_dim // 2, embedding_dim)
        )
        
        # Decoder (for autoencoder training)
        self.decoder = nn.Sequential(
            nn.Linear(embedding_dim, hidden_dim // 2),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(hidden_dim // 2, hidden_dim),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(hidden_dim, input_dim)
        )
        
    def forward(self, x):
        embedding = self.encoder(x)
        reconstruction = self.decoder(embedding)
        return embedding, reconstruction
    
    def get_embedding(self, x):
        with torch.no_grad():
            return self.encoder(x)


def extract_functions(content: str, file_type: str, min_lines: int = 5) -> List[Dict]:
    """Extract functions from code files"""
    functions = []
    
    patterns = {
        '.ps1': r'function\s+(\w+).*?\{(.*?)\n\}',
        '.py': r'def\s+(\w+)\s*\([^)]*\):\s*\n((?:\s{4,}.*\n)*)',
        '.js': r'(?:function\s+(\w+)|(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s*)?\([^)]*\)\s*=>)\s*\{([^}]+)\}',
        '.java': r'(?:public|private|protected)?\s*(?:static\s*)?\w+\s+(\w+)\s*\([^)]*\)\s*\{([^}]+)\}',
        '.cs': r'(?:public|private|protected)?\s*(?:static\s*)?\w+\s+(\w+)\s*\([^)]*\)\s*\{([^}]+)\}',
    }
    
    pattern = patterns.get(file_type, patterns['.js'])
    
    for match in re.finditer(pattern, content, re.DOTALL | re.MULTILINE):
        if file_type == '.js':
            name = match.group(1) or match.group(2)
            body = match.group(3)
        else:
            name = match.group(1)
            body = match.group(2) if len(match.groups()) >= 2 else ""
            
        lines = body.strip().split('\n')
        if len(lines) >= min_lines:
            functions.append({
                'name': name,
                'body': body.strip(),
                'lines': len(lines),
                'file_type': file_type
            })
    
    return functions


def vectorize_functions(functions: List[Dict], feature_extractor: CodeFeatureExtractor) -> Tuple[np.ndarray, List[str]]:
    """Convert functions to feature vectors using multiple approaches"""
    feature_vectors = []
    feature_names = []
    
    for func in functions:
        # Structural features
        struct_features = feature_extractor.extract_structural_features(func['body'])
        
        # AST features (for Python)
        ast_features = feature_extractor.extract_ast_features(func['body'], func['file_type'])
        
        # Semantic features
        semantic_features = feature_extractor.extract_semantic_features(func['body'])
        
        # Combine all features
        combined_features = []
        
        # Add structural features
        for key, value in struct_features.items():
            combined_features.append(value)
            if len(feature_vectors) == 0:
                feature_names.append(f'struct_{key}')
        
        # Add AST features
        for key, value in ast_features.items():
            combined_features.append(value)
            if len(feature_vectors) == 0:
                feature_names.append(f'ast_{key}')
        
        # Add semantic features
        combined_features.extend(semantic_features)
        if len(feature_vectors) == 0:
            feature_names.extend([f'semantic_{i}' for i in range(len(semantic_features))])
        
        feature_vectors.append(combined_features)
    
    return np.array(feature_vectors), feature_names


def train_similarity_network(feature_vectors: np.ndarray, epochs: int = 100) -> CodeSimilarityNet:
    """Train neural network for code similarity"""
    # Normalize features
    scaler = StandardScaler()
    normalized_features = scaler.fit_transform(feature_vectors)
    
    # Convert to PyTorch tensors
    X = torch.FloatTensor(normalized_features)
    
    # Initialize network
    input_dim = X.shape[1]
    model = CodeSimilarityNet(input_dim)
    optimizer = torch.optim.Adam(model.parameters(), lr=0.001)
    
    # Training loop
    print(f"Training neural network ({epochs} epochs)...")
    for epoch in range(epochs):
        # Forward pass
        embeddings, reconstructions = model(X)
        
        # Reconstruction loss
        recon_loss = F.mse_loss(reconstructions, X)
        
        # Contrastive loss (encourage similar codes to have similar embeddings)
        # Simple version: minimize variance of embeddings
        embedding_variance = torch.var(embeddings, dim=0).mean()
        
        # Total loss
        loss = recon_loss + 0.1 * embedding_variance
        
        # Backward pass
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
        
        if (epoch + 1) % 20 == 0:
            print(f"  Epoch {epoch+1}/{epochs}, Loss: {loss.item():.4f}")
    
    return model, scaler


def find_similarities(embeddings: np.ndarray, threshold: float = 0.7) -> List[Dict]:
    """Find similar code pairs based on embeddings"""
    similarity_matrix = cosine_similarity(embeddings)
    
    similar_pairs = []
    n = similarity_matrix.shape[0]
    
    for i in range(n):
        for j in range(i + 1, n):
            score = similarity_matrix[i, j]
            if score >= threshold:
                similar_pairs.append({
                    'idx1': i,
                    'idx2': j,
                    'score': float(score)
                })
    
    return similarity_matrix, similar_pairs


def cluster_similar_functions(embeddings: np.ndarray, functions: List[Dict], threshold: float = 0.8) -> List[List[int]]:
    """Cluster similar functions based on embeddings"""
    similarity_matrix = cosine_similarity(embeddings)
    
    clusters = []
    used = set()
    
    for i in range(len(functions)):
        if i in used:
            continue
            
        cluster = [i]
        used.add(i)
        
        for j in range(i + 1, len(functions)):
            if j not in used and similarity_matrix[i, j] >= threshold:
                cluster.append(j)
                used.add(j)
        
        if len(cluster) > 1:
            clusters.append(cluster)
    
    return clusters


def main():
    parser = argparse.ArgumentParser(description='Code similarity analysis using neural networks')
    parser.add_argument('input_path', help='Path to analyze')
    parser.add_argument('--min-lines', type=int, default=5, help='Minimum function size')
    parser.add_argument('--threshold', type=float, default=0.7, help='Similarity threshold')
    parser.add_argument('--output-dir', default='.', help='Output directory')
    parser.add_argument('--timestamp', default='analysis', help='Timestamp for output files')
    parser.add_argument('--epochs', type=int, default=100, help='Training epochs')
    
    args = parser.parse_args()
    
    # Initialize feature extractor
    feature_extractor = CodeFeatureExtractor()
    
    # Collect all functions
    all_functions = []
    
    for root, dirs, files in os.walk(args.input_path):
        for file in files:
            ext = os.path.splitext(file)[1]
            if ext in ['.ps1', '.py', '.js', '.java', '.cs']:
                filepath = os.path.join(root, file)
                try:
                    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                    
                    functions = extract_functions(content, ext, args.min_lines)
                    for func in functions:
                        func['file'] = filepath
                        all_functions.append(func)
                        
                except Exception as e:
                    print(f"Error processing {filepath}: {e}", file=sys.stderr)
    
    print(f"Found {len(all_functions)} functions to analyze")
    
    if len(all_functions) < 2:
        print("Not enough functions to analyze")
        return
    
    # Vectorize functions
    print("Extracting features...")
    feature_vectors, feature_names = vectorize_functions(all_functions, feature_extractor)
    print(f"Generated {feature_vectors.shape[1]} features per function")
    
    # Train neural network
    model, scaler = train_similarity_network(feature_vectors, epochs=args.epochs)
    
    # Get embeddings
    with torch.no_grad():
        X_normalized = torch.FloatTensor(scaler.transform(feature_vectors))
        embeddings = model.get_embedding(X_normalized).numpy()
    
    print(f"Generated {embeddings.shape[1]}-dimensional embeddings")
    
    # Find similarities
    similarity_matrix, similar_pairs = find_similarities(embeddings, args.threshold)
    
    # Cluster functions
    clusters = cluster_similar_functions(embeddings, all_functions, threshold=0.8)
    
    # Save results
    results = {
        'total_functions': len(all_functions),
        'similar_pairs': len(similar_pairs),
        'clusters': len(clusters),
        'embedding_dim': embeddings.shape[1],
        'feature_count': feature_vectors.shape[1],
        'functions': all_functions,
        'similarities': similar_pairs,
        'clusters_detail': clusters,
        'feature_importance': {
            'top_features': feature_names[:20] if feature_names else [],
            'feature_stats': {
                'mean': feature_vectors.mean(axis=0).tolist()[:20],
                'std': feature_vectors.std(axis=0).tolist()[:20]
            }
        }
    }
    
    # Save JSON results
    output_path = os.path.join(args.output_dir, f'similarity_analysis_{args.timestamp}.json')
    with open(output_path, 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"Results saved to {output_path}")
    
    # Generate CSV table
    table_path = os.path.join(args.output_dir, f'similarity_table_{args.timestamp}.csv')
    with open(table_path, 'w') as f:
        f.write("Function1,File1,Function2,File2,Similarity,Lines1,Lines2\n")
        for pair in similar_pairs:
            f1 = all_functions[pair['idx1']]
            f2 = all_functions[pair['idx2']]
            f.write(f"{f1['name']},{os.path.basename(f1['file'])},{f2['name']},{os.path.basename(f2['file'])},{pair['score']:.3f},{f1['lines']},{f2['lines']}\n")
    
    print(f"Similarity table saved to {table_path}")
    
    # Save embeddings for visualization
    embeddings_path = os.path.join(args.output_dir, f'embeddings_{args.timestamp}.npy')
    np.save(embeddings_path, embeddings)
    print(f"Embeddings saved to {embeddings_path}")


if __name__ == "__main__":
    main()