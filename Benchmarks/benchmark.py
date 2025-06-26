#!/usr/bin/env python3
"""
OpenGL Polar Sphere Benchmark
Renders various mathematical patterns as points on polar spheres
Tests GPU performance with different density levels and algorithms
"""

import pygame
import numpy as np
import OpenGL.GL as gl
import OpenGL.GLU as glu
import math
import time
import json
import argparse
import sys
from datetime import datetime
from threading import Thread
import random

class PolarSpherePattern:
    """Base class for polar sphere pattern generators"""
    
    def __init__(self, name, description):
        self.name = name
        self.description = description
        self.points = []
        self.colors = []
    
    def generate(self, density):
        """Generate points for the pattern - override in subclasses"""
        raise NotImplementedError
    
    def get_point_count(self):
        return len(self.points)

class FibonacciSphere(PolarSpherePattern):
    """Fibonacci spiral on sphere surface"""
    
    def __init__(self):
        super().__init__("Fibonacci Sphere", "Golden ratio spiral distribution")
    
    def generate(self, density):
        self.points = []
        self.colors = []
        
        # Much higher point density for stress testing
        n_points = int(density * 10000)  # Increased from 1000
        golden_ratio = (1 + math.sqrt(5)) / 2
        
        for i in range(n_points):
            # Fibonacci spiral
            theta = 2 * math.pi * i / golden_ratio
            phi = math.acos(1 - 2 * i / n_points)
            
            # Convert to Cartesian
            x = math.sin(phi) * math.cos(theta)
            y = math.sin(phi) * math.sin(theta)
            z = math.cos(phi)
            
            self.points.append([x, y, z])
            
            # More complex color calculations for CPU load
            r = abs(math.sin(theta * 3.7 + time.time() * 0.1)) * (x + 1) / 2
            g = abs(math.cos(phi * 2.3 + time.time() * 0.15)) * (y + 1) / 2
            b = abs(math.sin((theta + phi) * 1.9 + time.time() * 0.05)) * (z + 1) / 2
            alpha = 0.8 + 0.2 * math.sin(i * 0.01)
            self.colors.append([r, g, b, alpha])

class PrimeSpiral(PolarSpherePattern):
    """Prime number spiral on sphere"""
    
    def __init__(self):
        super().__init__("Prime Spiral", "Prime numbers mapped to sphere coordinates")
    
    def is_prime(self, n):
        if n < 2:
            return False
        for i in range(2, int(math.sqrt(n)) + 1):
            if n % i == 0:
                return False
        return True
    
    def generate(self, density):
        self.points = []
        self.colors = []
        
        # Increased computational load
        max_num = int(density * 20000)  # Increased from 2000
        primes = []
        
        # More intensive prime calculation with trial division
        for n in range(2, max_num):
            is_prime = True
            sqrt_n = int(math.sqrt(n))
            for i in range(2, sqrt_n + 1):
                if n % i == 0:
                    is_prime = False
                    break
            if is_prime:
                primes.append(n)
        
        for i, prime in enumerate(primes):
            # More complex mapping calculations
            t = prime / max_num * 50 * math.pi  # Increased rotations
            phi = math.acos(1 - 2 * (i / len(primes)))
            
            # Add some mathematical complexity
            offset_x = math.sin(prime * 0.001) * 0.1
            offset_y = math.cos(prime * 0.0007) * 0.1
            
            x = math.sin(phi) * math.cos(t) + offset_x
            y = math.sin(phi) * math.sin(t) + offset_y
            z = math.cos(phi)
            
            self.points.append([x, y, z])
            
            # More intensive color calculations
            intensity = math.log(prime) / math.log(max_num)
            hue_shift = math.sin(prime * 0.01) * 0.5 + 0.5
            saturation = math.cos(i * 0.001) * 0.3 + 0.7
            self.colors.append([intensity * hue_shift, saturation, 1.0 - intensity, 0.9])

class MandelbrotSphere(PolarSpherePattern):
    """Mandelbrot set mapped to sphere"""
    
    def __init__(self):
        super().__init__("Mandelbrot Sphere", "Mandelbrot set iterations on sphere")
    
    def mandelbrot_iterations(self, c, max_iter=100):
        z = 0
        for n in range(max_iter):
            if abs(z) > 2:
                return n
            z = z*z + c
        return max_iter
    
    def generate(self, density):
        self.points = []
        self.colors = []
        
        # Higher resolution for more GPU stress
        resolution = int(density * 100)  # Increased from 50
        max_iter = int(density * 50)     # Increased from 20
        
        # Add multiple layers for 3D effect and more computation
        layers = 3
        
        for layer in range(layers):
            z_offset = (layer - 1) * 0.3  # Spread across Z
            
            for i in range(resolution):
                for j in range(resolution):
                    # Map to complex plane
                    x = (i / resolution - 0.5) * 4  # Wider range
                    y = (j / resolution - 0.5) * 4
                    c = complex(x + layer * 0.1, y + layer * 0.05)  # Layer variation
                    
                    iterations = self.mandelbrot_iterations(c, max_iter)
                    
                    if iterations < max_iter:
                        # More complex sphere mapping
                        theta = x * math.pi * (1 + layer * 0.2)
                        phi = y * math.pi / 2 + math.pi / 2
                        
                        # Add mathematical distortion
                        distortion = math.sin(iterations * 0.1) * 0.1
                        
                        sphere_x = (math.sin(phi) * math.cos(theta)) * (1 + distortion)
                        sphere_y = (math.sin(phi) * math.sin(theta)) * (1 + distortion)
                        sphere_z = math.cos(phi) + z_offset
                        
                        self.points.append([sphere_x, sphere_y, sphere_z])
                        
                        # Complex color mixing
                        intensity = iterations / max_iter
                        layer_hue = layer / layers
                        r = intensity * math.sin(layer_hue * math.pi)
                        g = 0.3 + layer_hue * 0.4
                        b = (1.0 - intensity) * math.cos(layer_hue * math.pi)
                        alpha = 0.7 + intensity * 0.3
                        self.colors.append([r, g, b, alpha])

class ParticleSystem(PolarSpherePattern):
    """Dynamic particle system with physics simulation"""
    
    def __init__(self):
        super().__init__("Particle System", "Physics-based particles with gravitational attraction")
        self.velocities = []
        self.masses = []
    
    def generate(self, density):
        self.points = []
        self.colors = []
        self.velocities = []
        self.masses = []
        
        n_particles = int(density * 5000)
        
        # Initialize particles randomly on sphere
        for i in range(n_particles):
            # Random point on sphere
            theta = random.uniform(0, 2 * math.pi)
            phi = random.uniform(0, math.pi)
            
            x = math.sin(phi) * math.cos(theta)
            y = math.sin(phi) * math.sin(theta)
            z = math.cos(phi)
            
            self.points.append([x, y, z])
            
            # Random initial velocity
            vx = random.uniform(-0.01, 0.01)
            vy = random.uniform(-0.01, 0.01)
            vz = random.uniform(-0.01, 0.01)
            self.velocities.append([vx, vy, vz])
            
            # Random mass
            mass = random.uniform(0.5, 2.0)
            self.masses.append(mass)
            
            # Color based on mass and position
            r = mass / 2.0
            g = abs(z)
            b = (abs(x) + abs(y)) / 2
            self.colors.append([r, g, b, 0.8])
    
    def update_physics(self, dt=0.001):
        """Update particle positions with N-body physics"""
        n = len(self.points)
        forces = [[0, 0, 0] for _ in range(n)]
        
        # Calculate gravitational forces (expensive O(n²) operation)
        G = 0.0001  # Gravitational constant
        for i in range(n):
            for j in range(i + 1, n):
                p1 = self.points[i]
                p2 = self.points[j]
                
                # Distance vector
                dx = p2[0] - p1[0]
                dy = p2[1] - p1[1]
                dz = p2[2] - p1[2]
                
                # Distance magnitude
                r = math.sqrt(dx*dx + dy*dy + dz*dz) + 0.001  # Avoid division by zero
                
                # Force magnitude
                f = G * self.masses[i] * self.masses[j] / (r*r)
                
                # Unit vector
                ux = dx / r
                uy = dy / r
                uz = dz / r
                
                # Apply forces
                forces[i][0] += f * ux
                forces[i][1] += f * uy
                forces[i][2] += f * uz
                
                forces[j][0] -= f * ux
                forces[j][1] -= f * uy
                forces[j][2] -= f * uz
        
        # Update velocities and positions
        for i in range(n):
            # Update velocity
            self.velocities[i][0] += forces[i][0] / self.masses[i] * dt
            self.velocities[i][1] += forces[i][1] / self.masses[i] * dt
            self.velocities[i][2] += forces[i][2] / self.masses[i] * dt
            
            # Update position
            self.points[i][0] += self.velocities[i][0] * dt
            self.points[i][1] += self.velocities[i][1] * dt
            self.points[i][2] += self.velocities[i][2] * dt
            
            # Normalize to keep on sphere surface
            mag = math.sqrt(self.points[i][0]**2 + self.points[i][1]**2 + self.points[i][2]**2)
            if mag > 0:
                self.points[i][0] /= mag
                self.points[i][1] /= mag
                self.points[i][2] /= mag
    """Lorenz attractor projected to sphere"""
    
    def __init__(self):
        super().__init__("Lorenz Attractor", "Chaotic system on sphere surface")
    
    def generate(self, density):
        self.points = []
        self.colors = []
        
        # Lorenz parameters with variations
        sigma = 10.0
        rho = 28.0
        beta = 8.0/3.0
        
        # Multiple attractors for increased complexity
        attractors = 3
        
        for attractor in range(attractors):
            # Vary parameters slightly for each attractor
            s = sigma + attractor * 2
            r = rho + attractor * 5
            b = beta + attractor * 0.5
            
            # Initial conditions
            x, y, z = 1.0 + attractor, 1.0 - attractor * 0.5, 1.0 + attractor * 0.3
            dt = 0.005  # Smaller timestep for more points
            steps = int(density * 5000)  # Increased from 2000
            
class LorenzAttractor(PolarSpherePattern):
    """Lorenz attractor projected to sphere"""
    
    def __init__(self):
        super().__init__("Lorenz Attractor", "Chaotic system on sphere surface")
    
    def generate(self, density):
        self.points = []
        self.colors = []
        
        # Lorenz parameters with variations
        sigma = 10.0
        rho = 28.0
        beta = 8.0/3.0
        
        # Multiple attractors for increased complexity
        attractors = 3
        
        for attractor in range(attractors):
            # Vary parameters slightly for each attractor
            s = sigma + attractor * 2
            r = rho + attractor * 5
            b = beta + attractor * 0.5
            
            # Initial conditions
            x, y, z = 1.0 + attractor, 1.0 - attractor * 0.5, 1.0 + attractor * 0.3
            dt = 0.005  # Smaller timestep for more points
            steps = int(density * 5000)  # Increased from 2000
            
            for i in range(steps):
                # Lorenz equations with additional complexity
                dx = s * (y - x) + math.sin(i * 0.001) * 0.1
                dy = x * (r - z) - y + math.cos(i * 0.0007) * 0.1
                dz = x * y - b * z + math.sin(x * 0.1) * 0.05
                
                x += dx * dt
                y += dy * dt
                z += dz * dt
                
                # Add some mathematical noise
                noise_x = math.sin(i * 0.01 + attractor) * 0.02
                noise_y = math.cos(i * 0.013 + attractor) * 0.02
                noise_z = math.sin(i * 0.007 + attractor) * 0.01
                
                # Normalize to sphere with noise
                magnitude = math.sqrt((x + noise_x)**2 + (y + noise_y)**2 + (z + noise_z)**2)
                if magnitude > 0:
                    norm_x = (x + noise_x) / magnitude
                    norm_y = (y + noise_y) / magnitude
                    norm_z = (z + noise_z) / magnitude
                    
                    self.points.append([norm_x, norm_y, norm_z])
                    
                    # Complex color calculations
                    t = i / steps
                    attractor_hue = attractor / attractors
                    r_color = t * math.sin(attractor_hue * 2 * math.pi)
                    g_color = math.sin(t * math.pi + attractor_hue * math.pi)
                    b_color = (1.0 - t) * math.cos(attractor_hue * 3 * math.pi)
                    alpha = 0.6 + 0.4 * math.sin(t * 4 * math.pi)
                    self.colors.append([abs(r_color), abs(g_color), abs(b_color), alpha])

class BenchmarkResult:
    """Stores benchmark results"""
    
    def __init__(self):
        self.pattern_results = {}
        self.system_info = {}
        self.timestamp = datetime.now().isoformat()
    
    def add_result(self, pattern_name, density, points, fps, render_time):
        if pattern_name not in self.pattern_results:
            self.pattern_results[pattern_name] = []
        
        self.pattern_results[pattern_name].append({
            'density': density,
            'points': points,
            'fps': fps,
            'render_time_ms': render_time * 1000
        })
    
    def save_to_file(self, filename):
        with open(filename, 'w') as f:
            json.dump({
                'timestamp': self.timestamp,
                'system_info': self.system_info,
                'results': self.pattern_results
            }, f, indent=2)
    
    def get_summary(self):
        summary = []
        for pattern, results in self.pattern_results.items():
            if results:
                max_fps = max(r['fps'] for r in results)
                max_points = max(r['points'] for r in results)
                summary.append(f"{pattern}: {max_fps:.1f} FPS, {max_points:,} points")
        return summary

class OpenGLBenchmark:
    """Main benchmark class"""
    
    def __init__(self, width=1920, height=1080, fullscreen=False):
        self.width = width
        self.height = height
        self.fullscreen = fullscreen
        self.patterns = [
            FibonacciSphere(),
            PrimeSpiral(),
            MandelbrotSphere(),
            LorenzAttractor(),
            ParticleSystem()
        ]
        self.result = BenchmarkResult()
        self.rotation = 0
        
    def init_pygame(self):
        """Initialize Pygame and OpenGL"""
        pygame.init()
        
        # Set OpenGL attributes
        pygame.display.gl_set_attribute(pygame.GL_DOUBLEBUFFER, 1)
        pygame.display.gl_set_attribute(pygame.GL_DEPTH_SIZE, 24)
        pygame.display.gl_set_attribute(pygame.GL_STENCIL_SIZE, 8)
        pygame.display.gl_set_attribute(pygame.GL_MULTISAMPLEBUFFERS, 1)
        pygame.display.gl_set_attribute(pygame.GL_MULTISAMPLESAMPLES, 4)
        
        # Create display
        flags = pygame.OPENGL | pygame.DOUBLEBUF
        if self.fullscreen:
            flags |= pygame.FULLSCREEN
            
        self.screen = pygame.display.set_mode((self.width, self.height), flags)
        pygame.display.set_caption("OpenGL Polar Sphere Benchmark")
        
        # Initialize OpenGL
        self.init_opengl()
        
    def init_opengl(self):
        """Setup OpenGL state"""
        gl.glEnable(gl.GL_DEPTH_TEST)
        gl.glEnable(gl.GL_POINT_SMOOTH)
        gl.glEnable(gl.GL_BLEND)
        gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA)
        
        # Enable additional features for stress testing
        gl.glEnable(gl.GL_POLYGON_SMOOTH)
        gl.glHint(gl.GL_POLYGON_SMOOTH_HINT, gl.GL_NICEST)
        gl.glHint(gl.GL_POINT_SMOOTH_HINT, gl.GL_NICEST)
        
        gl.glClearColor(0.05, 0.05, 0.1, 1.0)
        
        # Setup perspective
        gl.glMatrixMode(gl.GL_PROJECTION)
        gl.glLoadIdentity()
        glu.gluPerspective(45, self.width / self.height, 0.1, 50.0)
        
        gl.glMatrixMode(gl.GL_MODELVIEW)
        gl.glLoadIdentity()
        
        # Get GPU info
        vendor = gl.glGetString(gl.GL_VENDOR).decode('utf-8')
        renderer = gl.glGetString(gl.GL_RENDERER).decode('utf-8')
        version = gl.glGetString(gl.GL_VERSION).decode('utf-8')
        
        self.result.system_info['gpu_vendor'] = vendor
        self.result.system_info['gpu_renderer'] = renderer
        self.result.system_info['opengl_version'] = version
        
        print(f"GPU: {vendor} {renderer}")
        print(f"OpenGL: {version}")
        
    def render_pattern(self, pattern):
        """Render a pattern to the screen with enhanced effects"""
        gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT)
        
        gl.glLoadIdentity()
        gl.glTranslatef(0.0, 0.0, -3.0)
        
        # More complex rotation for additional GPU load
        gl.glRotatef(self.rotation, 1, 1, 0)
        gl.glRotatef(self.rotation * 0.7, 0, 1, 1)
        gl.glRotatef(self.rotation * 0.3, 1, 0, 1)
        
        # Update physics for particle system
        if isinstance(pattern, ParticleSystem):
            pattern.update_physics()
        
        # Render points with varying sizes for GPU stress
        point_count = len(pattern.points)
        
        # Use different rendering modes based on point count
        if point_count > 50000:
            # Use vertex arrays for large datasets
            vertices = np.array(pattern.points, dtype=np.float32)
            colors = np.array(pattern.colors, dtype=np.float32)
            
            gl.glEnableClientState(gl.GL_VERTEX_ARRAY)
            gl.glEnableClientState(gl.GL_COLOR_ARRAY)
            
            gl.glVertexPointer(3, gl.GL_FLOAT, 0, vertices)
            gl.glColorPointer(4, gl.GL_FLOAT, 0, colors)
            
            # Multiple point sizes for stress testing
            for size in [1.0, 2.0, 3.0]:
                gl.glPointSize(size)
                gl.glDrawArrays(gl.GL_POINTS, 0, point_count)
            
            gl.glDisableClientState(gl.GL_VERTEX_ARRAY)
            gl.glDisableClientState(gl.GL_COLOR_ARRAY)
        else:
            # Immediate mode with variable point sizes
            for size in [1.0, 2.0, 3.0]:
                gl.glPointSize(size)
                gl.glBegin(gl.GL_POINTS)
                
                for i, (point, color) in enumerate(zip(pattern.points, pattern.colors)):
                    # Add some per-vertex computation for CPU load
                    time_factor = time.time() * 0.1
                    brightness = 0.8 + 0.2 * math.sin(i * 0.01 + time_factor)
                    adjusted_color = [c * brightness for c in color[:3]] + [color[3]]
                    
                    gl.glColor4f(*adjusted_color)
                    gl.glVertex3f(*point)
                
                gl.glEnd()
        
        # Add some additional GPU load with overlays
        self.render_overlay_effects()
        
        pygame.display.flip()
    
    def render_overlay_effects(self):
        """Add overlay effects for additional GPU stress"""
        # Render semi-transparent spheres
        gl.glPushMatrix()
        gl.glColor4f(0.1, 0.2, 0.3, 0.1)
        
        # Multiple overlapping spheres
        for i in range(3):
            gl.glPushMatrix()
            gl.glRotatef(self.rotation + i * 120, 0, 1, 0)
            gl.glTranslatef(0.5, 0, 0)
            gl.glScalef(0.3, 0.3, 0.3)
            
            # Draw wireframe sphere for additional complexity
            glu.gluSphere(glu.gluNewQuadric(), 1.0, 20, 20)
            gl.glPopMatrix()
        
        gl.glPopMatrix()
        
    def benchmark_pattern(self, pattern, densities, duration_per_test=3.0):
        """Benchmark a specific pattern at different densities"""
        print(f"\nBenchmarking {pattern.name}...")
        
        for density in densities:
            print(f"  Density {density}x...", end=" ", flush=True)
            
            # Generate pattern
            start_gen = time.time()
            pattern.generate(density)
            gen_time = time.time() - start_gen
            
            point_count = pattern.get_point_count()
            print(f"{point_count:,} points generated in {gen_time:.3f}s", end=" ", flush=True)
            
            if point_count == 0:
                print("(skipped - no points)")
                continue
            
            # Benchmark rendering
            frames = 0
            start_time = time.time()
            total_render_time = 0
            
            while time.time() - start_time < duration_per_test:
                # Handle events
                for event in pygame.event.get():
                    if event.type == pygame.QUIT:
                        return False
                
                render_start = time.time()
                self.render_pattern(pattern)
                render_end = time.time()
                
                total_render_time += (render_end - render_start)
                frames += 1
                self.rotation += 1.0
                
                # Prevent system freeze
                if frames % 10 == 0:
                    pygame.time.wait(1)
            
            elapsed = time.time() - start_time
            fps = frames / elapsed if elapsed > 0 else 0
            avg_render_time = total_render_time / frames if frames > 0 else 0
            
            print(f"-> {fps:.1f} FPS, {avg_render_time*1000:.2f}ms/frame")
            
            self.result.add_result(pattern.name, density, point_count, fps, avg_render_time)
            
        return True
        
    def run_benchmark(self, densities=[0.5, 1.0, 2.0, 4.0, 8.0], duration=3.0):
        """Run the complete benchmark suite"""
        try:
            self.init_pygame()
            
            print("="*60)
            print("OpenGL Polar Sphere Benchmark")
            print("="*60)
            print(f"Resolution: {self.width}x{self.height}")
            print(f"Test duration: {duration}s per density level")
            print(f"Density levels: {densities}")
            
            for pattern in self.patterns:
                if not self.benchmark_pattern(pattern, densities, duration):
                    break
            
            # Save results
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"opengl_benchmark_{timestamp}.json"
            self.result.save_to_file(filename)
            
            print("\n" + "="*60)
            print("BENCHMARK SUMMARY")
            print("="*60)
            for line in self.result.get_summary():
                print(line)
            print(f"\nResults saved to: {filename}")
            
        except Exception as e:
            print(f"Benchmark error: {e}")
            return False
        finally:
            pygame.quit()
            
        return True

def main():
    parser = argparse.ArgumentParser(description='OpenGL Polar Sphere Benchmark')
    parser.add_argument('--width', type=int, default=1920, help='Window width')
    parser.add_argument('--height', type=int, default=1080, help='Window height')
    parser.add_argument('--fullscreen', action='store_true', help='Run in fullscreen')
    parser.add_argument('--duration', type=float, default=3.0, help='Test duration per density')
    parser.add_argument('--densities', nargs='+', type=float, 
                       default=[0.5, 1.0, 2.0, 4.0, 8.0], help='Density levels to test')
    parser.add_argument('--pattern', choices=['fibonacci', 'prime', 'mandelbrot', 'lorenz', 'particles'],
                       help='Test only specific pattern')
    
    args = parser.parse_args()
    
    # Check dependencies
    try:
        import pygame
        import numpy as np
    except ImportError as e:
        print(f"Missing dependency: {e}")
        print("Install with: pip install pygame numpy PyOpenGL")
        sys.exit(1)
    
    benchmark = OpenGLBenchmark(args.width, args.height, args.fullscreen)
    
    # Filter patterns if specific one requested
    if args.pattern:
        pattern_map = {
            'fibonacci': FibonacciSphere,
            'prime': PrimeSpiral,
            'mandelbrot': MandelbrotSphere,
            'lorenz': LorenzAttractor,
            'particles': ParticleSystem
        }
        benchmark.patterns = [pattern_map[args.pattern]()]
    
    success = benchmark.run_benchmark(args.densities, args.duration)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()