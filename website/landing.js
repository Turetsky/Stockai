// Initialize Supabase
const SUPABASE_URL = window.SUPABASE_URL;
const SUPABASE_ANON_KEY = window.SUPABASE_ANON_KEY;

const { createClient } = window.supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Check if already logged in
async function checkExistingSession() {
    try {
        if (window.location.hash.includes('type=recovery')) return;
        const { data } = await db.auth.getSession();
        if (data.session) {
            window.location.href = 'index.html';
        }
    } catch (error) {
        console.error('Session check error:', error);
    }
}

// Tab switching
const tabButtons = document.querySelectorAll('.tab-button');
const tabContents = document.querySelectorAll('.tab-content');

tabButtons.forEach(button => {
    button.addEventListener('click', () => {
        const tabName = button.getAttribute('data-tab');

        // Remove active class from all buttons and contents
        tabButtons.forEach(btn => btn.classList.remove('active'));
        tabContents.forEach(content => content.classList.remove('active'));

        // Add active class to clicked button and corresponding content
        button.classList.add('active');
        document.getElementById(tabName).classList.add('active');

        // Clear messages when switching tabs
        clearMessages();
    });
});

// Message display functions
function showMessage(elementId, message, type) {
    const messageDiv = document.getElementById(elementId);
    messageDiv.innerHTML = `<div class="message ${type}">${message}</div>`;
}

function clearMessages() {
    document.getElementById('login-message').innerHTML = '';
    document.getElementById('signup-message').innerHTML = '';
    document.getElementById('reset-message').innerHTML = '';
}

// Login form handler
document.getElementById('login-form').addEventListener('submit', async (e) => {
    e.preventDefault();

    const email = document.getElementById('login-email').value.trim();
    const password = document.getElementById('login-password').value;
    const button = document.getElementById('login-button');

    clearMessages();
    button.disabled = true;
    button.textContent = 'Signing in...';

    try {
        const { data, error } = await db.auth.signInWithPassword({
            email,
            password
        });

        if (error) {
            showMessage('login-message', error.message, 'error');
        } else {
            showMessage('login-message', 'Login successful! Redirecting...', 'success');
            setTimeout(() => {
                window.location.href = 'index.html';
            }, 1500);
        }
    } catch (error) {
        showMessage('login-message', 'An unexpected error occurred. Please try again.', 'error');
    } finally {
        button.disabled = false;
        button.textContent = 'Sign In';
    }
});

// Sign up form handler
document.getElementById('signup-form').addEventListener('submit', async (e) => {
    e.preventDefault();

    const displayName = document.getElementById('signup-name').value.trim();
    const email = document.getElementById('signup-email').value.trim();
    const password = document.getElementById('signup-password').value;
    const confirmPassword = document.getElementById('signup-confirm').value;
    const button = document.getElementById('signup-button');

    clearMessages();

    if (password !== confirmPassword) {
        showMessage('signup-message', 'Passwords do not match.', 'error');
        return;
    }

    if (password.length < 6) {
        showMessage('signup-message', 'Password must be at least 6 characters long.', 'error');
        return;
    }

    button.disabled = true;
    button.textContent = 'Creating account...';

    try {
        const { data, error } = await db.auth.signUp({
            email,
            password,
            options: {
                data: {
                    display_name: displayName
                }
            }
        });

        if (error) {
            showMessage('signup-message', error.message, 'error');
        } else if (data.user && data.session) {
            // Auto-confirmed signup
            showMessage('signup-message', 'Account created successfully! Redirecting...', 'success');
            setTimeout(() => {
                window.location.href = 'index.html';
            }, 1500);
        } else {
            // Email confirmation required
            showMessage('signup-message', 'Account created! Check your email for a confirmation link to complete sign up.', 'success');
            document.getElementById('signup-form').reset();
        }
    } catch (error) {
        showMessage('signup-message', 'An unexpected error occurred. Please try again.', 'error');
    } finally {
        button.disabled = false;
        button.textContent = 'Create Account';
    }
});

// Forgot password functionality
const forgotPasswordLink = document.getElementById('forgot-password-link');
const forgotPasswordForm = document.getElementById('forgot-password-form');
const loginForm = document.getElementById('login-form');
const backToLoginLink = document.getElementById('back-to-login-link');

forgotPasswordLink.addEventListener('click', (e) => {
    e.preventDefault();
    loginForm.style.display = 'none';
    forgotPasswordForm.style.display = 'block';
    clearMessages();
});

backToLoginLink.addEventListener('click', (e) => {
    e.preventDefault();
    loginForm.style.display = 'block';
    forgotPasswordForm.style.display = 'none';
    clearMessages();
});

document.getElementById('reset-button').addEventListener('click', async () => {
    const email = document.getElementById('reset-email').value.trim();
    const button = document.getElementById('reset-button');

    if (!email) {
        showMessage('reset-message', 'Please enter your email address.', 'error');
        return;
    }

    button.disabled = true;
    button.textContent = 'Sending...';

    try {
        const { error } = await db.auth.resetPasswordForEmail(email, {
                redirectTo: window.location.origin + '/landing.html'
            });

        if (error) {
            showMessage('reset-message', error.message, 'error');
        } else {
            showMessage('reset-message', 'Password reset link sent! Check your email.', 'success');
            document.getElementById('reset-email').value = '';
        }
    } catch (error) {
        showMessage('reset-message', 'An unexpected error occurred. Please try again.', 'error');
    } finally {
        button.disabled = false;
        button.textContent = 'Send Reset Link';
    }
});

function showRecoveryForm() {
    const tabs = document.querySelector('.tabs');
    if (tabs) tabs.style.display = 'none';
    document.querySelectorAll('.tab-content').forEach(el => el.style.display = 'none');
    // the recovery form lives inside the (now hidden) login tab — re-show its container
    document.getElementById('login').style.display = 'block';
    document.getElementById('login-form').style.display = 'none';
    document.getElementById('forgot-password-form').style.display = 'none';
    document.getElementById('new-password-form').style.display = 'block';
}

// Handle password recovery link (user arrives from reset email)
if (window.location.hash.includes('type=recovery')) {
    showRecoveryForm();
}

db.auth.onAuthStateChange(async (event, session) => {
    if (event === 'PASSWORD_RECOVERY') {
        showRecoveryForm();
    }
});

document.getElementById('new-password-button').addEventListener('click', async () => {
    const password = document.getElementById('new-password').value;
    const confirm = document.getElementById('new-password-confirm').value;
    const button = document.getElementById('new-password-button');

    if (password.length < 6) {
        showMessage('new-password-message', 'Password must be at least 6 characters.', 'error');
        return;
    }
    if (password !== confirm) {
        showMessage('new-password-message', 'Passwords do not match.', 'error');
        return;
    }

    button.disabled = true;
    button.textContent = 'Updating...';

    try {
        const { error } = await db.auth.updateUser({ password });
        if (error) {
            showMessage('new-password-message', error.message, 'error');
        } else {
            showMessage('new-password-message', 'Password updated! Redirecting...', 'success');
            setTimeout(() => { window.location.href = 'index.html'; }, 1500);
        }
    } catch (err) {
        showMessage('new-password-message', 'An unexpected error occurred.', 'error');
    } finally {
        button.disabled = false;
        button.textContent = 'Update Password';
    }
});

// Initialize app
checkExistingSession();
